"""HW-2 hw_bridge smoke: real-bridge link path with an in-process fake bridge.

Topology under test (all in this script, no real hardware, no credentials):
  WS client → gateway(--physics hw_bridge) → fake arm-bridge (hello/state/joint_targets)

Assertions: hello feature flag, scene, UNKNOWN_JOINT rejection, rad→counts
translation + bridge-side soft-limit clamp, present-state rad round-trip.

Run: .venv/bin/python scripts/hw_bridge_smoke.py
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import websockets
from websockets.exceptions import ConnectionClosed

ROOT = Path(__file__).resolve().parents[1]
FAKE_PORT = 8767
GW_PORT = 8765

## Fake bridge machine table (public-style params; 1000..3000 counts window).
POS_MIN = {1: 1000, 2: 1000, 3: 1000, 4: 1000, 5: 1000, 6: 1000}
POS_MAX = {1: 3000, 2: 3000, 3: 3000, 4: 3000, 5: 3000, 6: 3000}
HOME = {m: (POS_MIN[m] + POS_MAX[m]) // 2 for m in POS_MIN}
RATE = 400.0  # counts/s


class FakeBridge:
    def __init__(self) -> None:
        self.present = {m: float(HOME[m]) for m in HOME}
        self.goal = dict(self.present)
        self.clients: set = set()

    async def handler(self, ws) -> None:
        await ws.send(json.dumps({
            "type": "hello",
            "protocol": "so101-arm.v0-fake",
            "physics": "fake",
            "joints": {str(m): n for m, n in
                       ((1, "shoulder_pan"), (2, "shoulder_lift"), (3, "elbow_flex"),
                        (4, "wrist_flex"), (5, "wrist_roll"), (6, "gripper"))},
            "pos_min": {str(k): v for k, v in POS_MIN.items()},
            "pos_max": {str(k): v for k, v in POS_MAX.items()},
        }))
        self.clients.add(ws)
        try:
            async for frame in ws:
                msg = json.loads(frame)
                if msg.get("type") == "joint_targets":
                    for k, v in (msg.get("goal") or {}).items():
                        mid = int(k)
                        self.goal[mid] = max(POS_MIN[mid], min(POS_MAX[mid], float(v)))
                    await ws.send(json.dumps({"type": "joint_targets_ack",
                                              "goal": msg.get("goal")}))
        except ConnectionClosed:
            pass
        finally:
            self.clients.discard(ws)

    async def tick_loop(self) -> None:
        dt = 0.05
        while True:
            for m in self.present:
                delta = self.goal[m] - self.present[m]
                step = max(-RATE * dt, min(RATE * dt, delta))
                self.present[m] += step
            if self.clients:
                frame = json.dumps({
                    "type": "state",
                    "present": {str(m): int(round(p)) for m, p in self.present.items()},
                    "goal": {str(m): int(round(g)) for m, g in self.goal.items()},
                })
                await asyncio.gather(
                    *(c.send(frame) for c in list(self.clients)),
                    return_exceptions=True,
                )
            await asyncio.sleep(dt)


async def _recv_type(ws, want: str, timeout: float = 8.0) -> dict:
    while True:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if msg.get("type") == want:
            return msg
        if msg.get("type") == "error":
            raise AssertionError(f"gateway error while waiting for {want}: {msg}")


async def _recv_state_with(ws, entity_id: str, timeout: float = 10.0) -> dict:
    while True:
        msg = await _recv_type(ws, "state", timeout=timeout)
        ent = next((e for e in msg["payload"]["entities"]
                    if e.get("entity_id") == entity_id), None)
        if ent is not None:
            return ent


async def _wait_joint(ws, entity_id: str, joint: str, lo: float, hi: float,
                      timeout: float = 12.0) -> dict:
    """Drain state frames until joint ∈ [lo, hi] (buffered frames are stale)."""
    deadline = time.monotonic() + timeout
    last: dict = {}
    while time.monotonic() < deadline:
        ent = await _recv_state_with(ws, entity_id, timeout=timeout)
        last = ent
        v = float(ent["joints"].get(joint, 0.0))
        if lo <= v <= hi:
            return ent
    raise AssertionError(f"{joint} never reached [{lo},{hi}]; last={last.get('joints')}")


async def client_flow() -> None:
    async with websockets.connect(f"ws://127.0.0.1:{GW_PORT}") as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert "hw_bridge_link" in (hello["payload"].get("features") or []), hello
        sid = hello["session_id"]
        print("hello ok ·", hello["payload"]["features"])

        await ws.send(json.dumps({"type": "join", "session_id": sid,
                                  "payload": {"level_id": "demo_arm_lab",
                                              "player_name": "hw2_smoke"}}))
        scene = await _recv_type(ws, "scene")
        assert scene["payload"]["level_id"] == "demo_arm_lab", scene
        print("scene ok")

        await ws.send(json.dumps({"type": "cmd", "session_id": sid,
                                  "payload": {"action": "take_control",
                                              "entity_id": "arm_0"}}))

        await ws.send(json.dumps({"type": "cmd", "session_id": sid,
                                  "payload": {"entity_id": "arm_0",
                                              "joint_targets": {"nope": 1.0}}}))
        err = await _recv_type(ws, "error")
        assert err["payload"]["code"] == "UNKNOWN_JOINT", err
        print("unknown joint rejected ok")

        # shoulder_pan 0.5 rad → mid-window counts (flip=1 → t inverted).
        await ws.send(json.dumps({"type": "cmd", "session_id": sid,
                                  "payload": {"entity_id": "arm_0",
                                              "joint_targets": {"shoulder_pan": 0.5}}}))
        ent = await _wait_joint(ws, "arm_0", "shoulder_pan", 0.38, 0.62)
        pan = ent["joints"]["shoulder_pan"]
        assert ent["extensions"]["mw"]["hw_enabled"] is True, ent
        print("bridge round-trip ok · shoulder_pan =", round(pan, 3))

        # Beyond soft limit → clamped to 1.92 rad window edge.
        await ws.send(json.dumps({"type": "cmd", "session_id": sid,
                                  "payload": {"entity_id": "arm_0",
                                              "joint_targets": {"shoulder_pan": 9.9}}}))
        ent = await _wait_joint(ws, "arm_0", "shoulder_pan", 1.5, 1.92 + 1e-6)
        print("soft-limit clamp ok · shoulder_pan =", round(ent["joints"]["shoulder_pan"], 3))


async def main() -> int:
    bridge = FakeBridge()
    server = await websockets.serve(bridge.handler, "127.0.0.1", FAKE_PORT)
    ticker = asyncio.create_task(bridge.tick_loop())

    env = dict(os.environ)
    env["MW_HW_BRIDGE_URL"] = f"ws://127.0.0.1:{FAKE_PORT}"
    env.pop("MW_HW_BRIDGE_TOKEN", None)
    gw = subprocess.Popen(
        [sys.executable, str(ROOT / "gateway" / "echo_server.py"),
         "--physics", "hw_bridge", "--port", str(GW_PORT), "--admin-port", "0",
         "--no-record"],
        cwd=str(ROOT), env=env,
        stdout=open("/tmp/hw2_gw.log", "w"), stderr=subprocess.STDOUT,
    )
    try:
        for _ in range(40):
            await asyncio.sleep(0.25)
            try:
                async with websockets.connect(f"ws://127.0.0.1:{GW_PORT}",
                                              open_timeout=1) as probe:
                    pass
                break
            except OSError:
                if gw.poll() is not None:
                    raise RuntimeError("gateway exited early")
        else:
            raise RuntimeError("gateway did not start listening")
        await client_flow()
    finally:
        gw.terminate()
        try:
            gw.wait(timeout=5)
        except subprocess.TimeoutExpired:
            gw.kill()
        ticker.cancel()
        server.close()
        await server.wait_closed()
    print("hw_bridge smoke OK")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except (AssertionError, asyncio.TimeoutError, OSError, RuntimeError) as exc:
        print(f"hw_bridge smoke FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
