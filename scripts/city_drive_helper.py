"""Closed-loop helpers to reach demo_city finish (SW spawn → NE goal)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPO / "examples" / "contracts" / "demo_city.json"


def load_city_finish() -> tuple[float, float, float, float]:
    """Return (spawn_x, spawn_y, finish_x, finish_y) from current contract."""
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    spawns = contract.get("mech_spawns") or []
    sp = (spawns[0] or {}).get("pose") or {}
    trigger = next(
        (t for t in (contract.get("triggers") or []) if t.get("id") == "trigger_finish"),
        None,
    )
    if trigger and trigger.get("type") == "aabb":
        mn = trigger["min"]
        mx = trigger["max"]
        fx = 0.5 * (float(mn[0]) + float(mx[0]))
        fy = 0.5 * (float(mn[1]) + float(mx[1]))
    else:
        fx = fy = 0.0
    return float(sp.get("x", 0.0)), float(sp.get("y", 0.0)), fx, fy


def manhattan_cmd(
    x: float,
    y: float,
    finish_x: float,
    finish_y: float,
    *,
    turn_x: float | None = None,
) -> tuple[float, float]:
    """Body-frame vx/vy with yaw≈0: east then north (or to finish).

    Path: drive +x to east street (turn_x), then +y to finish_y, then nudge to finish.
    """
    tx = finish_x if turn_x is None else turn_x
    if abs(x - tx) > 1.2:
        return (1.0 if tx > x else -1.0), 0.0
    if abs(y - finish_y) > 1.2:
        return 0.0, (1.0 if finish_y > y else -1.0)
    dx = finish_x - x
    dy = finish_y - y
    scale = max(abs(dx), abs(dy), 0.01)
    return max(-1.0, min(1.0, dx / scale)), max(-1.0, min(1.0, dy / scale))


def entity_xy(state_payload: dict[str, Any], entity_id: str = "mech_player") -> tuple[float, float]:
    """Extract base_pose x,y from a state payload."""
    entities = state_payload.get("entities") or []
    ent = next((e for e in entities if e.get("entity_id") == entity_id), entities[0] if entities else {})
    pose = ent.get("base_pose") or {}
    return float(pose.get("x", 0.0)), float(pose.get("y", 0.0))
