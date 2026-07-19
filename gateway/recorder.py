"""Session recorder: header.json + frames.jsonl beside the Gateway sim loop."""

from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

LOG = logging.getLogger("mineworld.recorder")

RECORDING_VERSION = "0.1"


def _utc_now_iso() -> str:
    """Return UTC now as ISO-8601 with Z suffix."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def contract_hash(contract: dict[str, Any]) -> str:
    """Stable SHA-256 of canonical contract JSON."""
    raw = json.dumps(contract, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _il_fields_from_contract(contract: dict[str, Any]) -> dict[str, Any]:
    """Derive IL labeling fields from scene contract (V4a)."""
    ext_root = contract.get("extensions") or {}
    mw_il = ext_root.get("mw.il") if isinstance(ext_root, dict) else {}
    if not isinstance(mw_il, dict):
        mw_il = {}
    task_id = mw_il.get("task_id")
    if not task_id:
        objectives = contract.get("objectives") or []
        if objectives and isinstance(objectives[0], dict):
            task_id = objectives[0].get("id")
    difficulty = mw_il.get("difficulty") or "poc"
    modes: list[str] = []
    for spawn in contract.get("mech_spawns") or []:
        if not isinstance(spawn, dict):
            continue
        mode = spawn.get("control_mode")
        if mode and mode not in modes:
            modes.append(str(mode))
    tags = [str(t) for t in (contract.get("tags") or [])]
    primary = None
    if len(modes) == 1:
        primary = modes[0]
    elif modes:
        primary = modes[0]
    return {
        "task_id": task_id,
        "difficulty": str(difficulty),
        "control_mode": primary,
        "control_modes": modes,
        "tags": tags,
    }


class SessionRecorder:
    """Write one session directory: header.json + frames.jsonl."""

    def __init__(
        self,
        root: Path,
        *,
        session_id: str,
        contract: dict[str, Any],
        protocol_version: str,
        dt: float,
        sim_hz: int,
        state_hz: int,
        record_every_n_ticks: int = 1,
        features: list[str] | None = None,
        software: dict[str, Any] | None = None,
    ) -> None:
        self.session_id = session_id
        self.dt = dt
        self.record_every_n_ticks = max(1, record_every_n_ticks)
        self.num_frames = 0
        self._last_tick = 0
        self._closed = False

        self.dir = root / session_id
        self.dir.mkdir(parents=True, exist_ok=True)
        self.header_path = self.dir / "header.json"
        self.frames_path = self.dir / "frames.jsonl"
        self._fp = self.frames_path.open("w", encoding="utf-8")

        spawns = contract.get("mech_spawns") or []
        mech_refs = [s["model_ref"] for s in spawns if s.get("model_ref")]
        il = _il_fields_from_contract(contract)

        self._header: dict[str, Any] = {
            "recording_version": RECORDING_VERSION,
            "session_id": session_id,
            "protocol_version": protocol_version,
            "contract_version": contract.get("contract_version", "0.1"),
            "contract_hash": contract_hash(contract),
            "level_id": contract.get("level_id"),
            "seed": contract.get("seed"),
            "task_id": il["task_id"],
            "difficulty": il["difficulty"],
            "control_mode": il["control_mode"],
            "control_modes": il["control_modes"],
            "tags": il["tags"],
            "frame": contract.get("frame", "mineworld_zup_m"),
            "dt": dt,
            "sim_hz": sim_hz,
            "state_hz": state_hz,
            "record_every_n_ticks": self.record_every_n_ticks,
            "mech_model_refs": mech_refs,
            "started_at": _utc_now_iso(),
            "ended_at": None,
            "outcome": "running",
            "scene_contract": contract,
            "features": list(features or []),
            "software": software or {},
            "stats": {"num_frames": 0, "duration_sim_s": 0.0},
        }
        self._flush_header()
        LOG.info("recording started session=%s dir=%s", session_id, self.dir)

    def _flush_header(self) -> None:
        """Rewrite header.json from in-memory state."""
        self.header_path.write_text(
            json.dumps(self._header, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def should_record(self, tick: int) -> bool:
        """Return True if this sim tick should append a frame."""
        return tick % self.record_every_n_ticks == 0

    def set_outcome(self, outcome: str) -> None:
        """Update header outcome while the session is still running."""
        if self._closed:
            return
        self._header["outcome"] = outcome
        self._flush_header()

    def write_frame(
        self,
        *,
        tick: int,
        cmd: dict[str, Any] | None,
        state: dict[str, Any] | None,
        events: list[dict[str, Any]] | None = None,
    ) -> None:
        """Append one JSONL frame for the given tick."""
        if self._closed:
            return
        if not self.should_record(tick):
            return
        frame: dict[str, Any] = {
            "tick": tick,
            "t_sim": round(tick * self.dt, 6),
            "cmd": cmd,
            "state": state,
            "events": list(events or []),
        }
        self._fp.write(json.dumps(frame, ensure_ascii=False, separators=(",", ":")) + "\n")
        self.num_frames += 1
        self._last_tick = tick
        # Periodic flush so a crash still leaves usable JSONL.
        if self.num_frames % 50 == 0:
            self._fp.flush()

    def close(self, outcome: str = "disconnect") -> Path:
        """Finalize header stats and close the frames file."""
        if self._closed:
            return self.dir
        self._closed = True
        self._fp.flush()
        self._fp.close()
        duration = round(self._last_tick * self.dt, 6)
        self._header["ended_at"] = _utc_now_iso()
        self._header["outcome"] = outcome
        self._header["stats"] = {
            "num_frames": self.num_frames,
            "duration_sim_s": duration,
        }
        self._flush_header()
        LOG.info(
            "recording closed session=%s frames=%d duration_sim_s=%.2f outcome=%s",
            self.session_id,
            self.num_frames,
            duration,
            outcome,
        )
        return self.dir
