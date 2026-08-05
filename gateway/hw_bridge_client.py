"""HW-2: client for the closed external arm-bridge (ADR-004).

Speaks the bridge's public WS semantics (hello/state/joint_targets) and
maps Feetech counts <-> URDF radians with a linear soft-limit mapping
(flip = reversed joint direction; pan is reversed on SO-101).

The bridge endpoint/credentials NEVER live in this repo: URL/token come
from MW_HW_BRIDGE_URL / MW_HW_BRIDGE_TOKEN at process start.
"""

from __future__ import annotations

import asyncio
import json
import logging
import math
import os
from dataclasses import dataclass, field
from typing import Any

import websockets

LOG = logging.getLogger("mineworld.hw_bridge")

ENV_URL = "MW_HW_BRIDGE_URL"
ENV_TOKEN = "MW_HW_BRIDGE_TOKEN"

## Joint name <-> motor id (public SO-101 convention; pan direction flipped).
NAME_TO_MID: dict[str, int] = {
    "shoulder_pan": 1,
    "shoulder_lift": 2,
    "elbow_flex": 3,
    "wrist_flex": 4,
    "wrist_roll": 5,
    "gripper": 6,
}
MID_TO_NAME: dict[int, str] = {v: k for k, v in NAME_TO_MID.items()}
FLIP_MIDS: frozenset[int] = frozenset({1})
## Public URDF-class rad ranges (same as hw_machines.SO101 profile).
RAD_RANGE: dict[int, tuple[float, float]] = {
    1: (-1.92, 1.92),
    2: (-1.75, 1.75),
    3: (-1.69, 1.69),
    4: (-1.66, 1.66),
    5: (-2.74, 2.74),
    6: (-0.17, 1.75),
}


def _map_range(counts: float, c_lo: float, c_hi: float, r_lo: float, r_hi: float, flip: bool) -> float:
    span = max(1e-6, c_hi - c_lo)
    t = max(0.0, min(1.0, (counts - c_lo) / span))
    if flip:
        t = 1.0 - t
    return r_lo + t * (r_hi - r_lo)


def _unmap_range(rad: float, c_lo: float, c_hi: float, r_lo: float, r_hi: float, flip: bool) -> float:
    span = max(1e-6, r_hi - r_lo)
    t = max(0.0, min(1.0, (rad - r_lo) / span))
    if flip:
        t = 1.0 - t
    return c_lo + t * (c_hi - c_lo)


@dataclass
class HwBridgeClient:
    """Async WS client: present-state cache + fire-and-forget outbox."""

    url: str
    token: str = ""
    pos_min: dict[int, float] = field(default_factory=dict)
    pos_max: dict[int, float] = field(default_factory=dict)
    present_rad: dict[str, float] = field(default_factory=dict)
    connected: bool = False
    protocol: str = ""
    _ws: Any = None
    _outbox: asyncio.Queue = field(default_factory=asyncio.Queue)
    _tasks: list[asyncio.Task] = field(default_factory=list)
    _stopping: bool = False

    @classmethod
    def from_env(cls) -> "HwBridgeClient | None":
        url = str(os.environ.get(ENV_URL) or "").strip()
        if not url:
            return None
        return cls(url=url, token=str(os.environ.get(ENV_TOKEN) or "").strip())

    def _full_url(self) -> str:
        if not self.token:
            return self.url
        sep = "&" if "?" in self.url else "?"
        return f"{self.url}{sep}token={self.token}"

    async def start(self) -> None:
        """Connect, await hello, then run recv/writer loops with reconnect."""
        self._stopping = False
        self._tasks.append(asyncio.create_task(self._run()))

    async def stop(self) -> None:
        self._stopping = True
        try:
            self._outbox.put_nowait({"type": "cmd", "enable": False, "dq": {}})
        except asyncio.QueueFull:
            pass
        for t in self._tasks:
            t.cancel()
        self._tasks.clear()
        if self._ws is not None:
            try:
                await self._ws.close()
            except Exception:  # noqa: BLE001
                pass
        self.connected = False

    async def _run(self) -> None:
        backoff = 1.0
        while not self._stopping:
            try:
                async with websockets.connect(self._full_url(), open_timeout=8) as ws:
                    self._ws = ws
                    raw = await asyncio.wait_for(ws.recv(), timeout=8)
                    hello = json.loads(raw)
                    if hello.get("type") != "hello":
                        raise RuntimeError(f"bridge first frame not hello: {hello!r}")
                    self._apply_hello(hello)
                    self.connected = True
                    backoff = 1.0
                    LOG.info("hw_bridge connected protocol=%s joints=%s",
                             self.protocol, sorted(self.present_rad))
                    writer = asyncio.create_task(self._writer(ws))
                    try:
                        async for frame in ws:
                            self._handle_frame(frame)
                    finally:
                        writer.cancel()
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                LOG.warning("hw_bridge link down: %s (retry %.0fs)", exc, backoff)
            finally:
                self.connected = False
                self._ws = None
            await asyncio.sleep(backoff)
            backoff = min(15.0, backoff * 2.0)

    async def _writer(self, ws: Any) -> None:
        while True:
            msg = await self._outbox.get()
            try:
                await ws.send(json.dumps(msg))
            except Exception as exc:  # noqa: BLE001
                LOG.warning("hw_bridge send fail: %s", exc)
                return

    def _apply_hello(self, hello: dict[str, Any]) -> None:
        self.protocol = str(hello.get("protocol") or "")
        for key, table in (("pos_min", self.pos_min), ("pos_max", self.pos_max)):
            raw = hello.get(key)
            if isinstance(raw, dict):
                table.clear()
                for k, v in raw.items():
                    try:
                        table[int(k)] = float(v)
                    except (TypeError, ValueError):
                        continue

    def _handle_frame(self, frame: Any) -> None:
        try:
            msg = json.loads(frame)
        except (TypeError, ValueError):
            return
        if msg.get("type") != "state":
            return
        present = msg.get("present")
        if not isinstance(present, dict):
            return
        for k, v in present.items():
            try:
                mid = int(k)
                counts = float(v)
            except (TypeError, ValueError):
                continue
            name = MID_TO_NAME.get(mid)
            if name is None:
                continue
            self.present_rad[name] = self.counts_to_rad(mid, counts)

    ## --- unit mapping (linear over soft limits; flip for reversed joints) ---

    def counts_to_rad(self, mid: int, counts: float) -> float:
        r_lo, r_hi = RAD_RANGE.get(mid, (-math.pi, math.pi))
        c_lo = self.pos_min.get(mid, 0.0)
        c_hi = self.pos_max.get(mid, 4095.0)
        return _map_range(counts, c_lo, c_hi, r_lo, r_hi, mid in FLIP_MIDS)

    def rad_to_counts(self, mid: int, rad: float) -> float:
        r_lo, r_hi = RAD_RANGE.get(mid, (-math.pi, math.pi))
        c_lo = self.pos_min.get(mid, 0.0)
        c_hi = self.pos_max.get(mid, 4095.0)
        return _unmap_range(rad, c_lo, c_hi, r_lo, r_hi, mid in FLIP_MIDS)

    ## --- commands (fire-and-forget; bridge owns safety clamps) ---

    def send_joint_targets_rad(self, targets_rad: dict[str, float]) -> None:
        goal: dict[str, int] = {}
        for name, rad in targets_rad.items():
            mid = NAME_TO_MID.get(name)
            if mid is None:
                continue
            goal[str(mid)] = int(round(self.rad_to_counts(mid, float(rad))))
        if not goal:
            return
        self._outbox.put_nowait({"type": "joint_targets", "goal": goal})
