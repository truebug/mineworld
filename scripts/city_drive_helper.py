"""Closed-loop helpers to reach finish AABB (city / race contracts)."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
CITY_CONTRACT = REPO / "examples" / "contracts" / "demo_city.json"
RACE_CONTRACT = REPO / "examples" / "contracts" / "demo_race.json"
RACE_LAYOUT = REPO / "godot" / "spike" / "data" / "race_layout.json"


def load_finish(
    contract_path: Path | None = None,
) -> tuple[float, float, float, float]:
    """Return (spawn_x, spawn_y, finish_x, finish_y) from contract."""
    path = contract_path or CITY_CONTRACT
    contract = json.loads(path.read_text(encoding="utf-8"))
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


def load_city_finish() -> tuple[float, float, float, float]:
    """Compat: demo_city finish."""
    return load_finish(CITY_CONTRACT)


def load_race_finish() -> tuple[float, float, float, float]:
    """demo_race finish gate center."""
    return load_finish(RACE_CONTRACT)


def load_race_waypoints() -> list[tuple[float, float]]:
    """Centerline points ordered from start → … → finish (almost full lap)."""
    layout = json.loads(RACE_LAYOUT.read_text(encoding="utf-8"))
    cl = layout.get("centerline") or []
    start_i = int(layout.get("start_index", 0))
    finish_i = int(layout.get("finish_index", max(0, len(cl) - 1)))
    n = len(cl)
    if n == 0:
        return []
    out: list[tuple[float, float]] = []
    i = start_i
    for _ in range(n + 1):
        p = cl[i % n]
        out.append((float(p["x"]), float(p["y"])))
        if i % n == finish_i and len(out) > 3:
            break
        i += 1
    return out


def race_chase_cmd(
    x: float,
    y: float,
    yaw: float,
    target: tuple[float, float],
    *,
    speed: float = 1.0,
    stuck: bool = False,
) -> tuple[float, float, float]:
    """Body-frame throttle/steer [-1,1] toward a world XY waypoint (wheel torque)."""
    tx, ty = target
    dx, dy = tx - x, ty - y
    dist = math.hypot(dx, dy)
    if dist < 1e-3:
        return 0.0, 0.0, 0.0
    want = math.atan2(dy, dx)
    err = (want - yaw + math.pi) % (2 * math.pi) - math.pi
    if stuck:
        # Reverse while steering (Ackermann cannot spot-turn).
        return -0.65, 0.0, 1.0 if err >= 0.0 else -1.0
    yaw_rate = max(-1.0, min(1.0, err * 2.2))
    if abs(err) > 1.2:
        return -0.25, 0.0, yaw_rate
    turn_slow = 1.0 / (1.0 + 1.6 * abs(err))
    forward = max(0.35, math.cos(err)) * turn_slow
    thr = max(-1.0, min(1.0, float(speed))) * forward
    return thr, 0.0, yaw_rate


def manhattan_cmd(
    x: float,
    y: float,
    finish_x: float,
    finish_y: float,
    *,
    turn_x: float | None = None,
) -> tuple[float, float]:
    """Body-frame vx/vy with yaw≈0: east then north (or to finish)."""
    tx = finish_x if turn_x is None else turn_x
    if abs(x - tx) > 1.2:
        return (1.0 if tx > x else -1.0), 0.0
    if abs(y - finish_y) > 1.2:
        return 0.0, (1.0 if finish_y > y else -1.0)
    dx = finish_x - x
    dy = finish_y - y
    scale = max(abs(dx), abs(dy), 0.01)
    return max(-1.0, min(1.0, dx / scale)), max(-1.0, min(1.0, dy / scale))


def entity_xy(
    state_payload: dict[str, Any], entity_id: str = "mech_player"
) -> tuple[float, float]:
    """Extract base_pose x,y from a state payload."""
    entities = state_payload.get("entities") or []
    ent = next(
        (e for e in entities if e.get("entity_id") == entity_id),
        entities[0] if entities else {},
    )
    pose = ent.get("base_pose") or {}
    return float(pose.get("x", 0.0)), float(pose.get("y", 0.0))


def entity_xy_yaw(
    state_payload: dict[str, Any], entity_id: str = "mech_player"
) -> tuple[float, float, float]:
    """Extract base_pose x,y,yaw from a state payload."""
    entities = state_payload.get("entities") or []
    ent = next(
        (e for e in entities if e.get("entity_id") == entity_id),
        entities[0] if entities else {},
    )
    pose = ent.get("base_pose") or {}
    return (
        float(pose.get("x", 0.0)),
        float(pose.get("y", 0.0)),
        float(pose.get("yaw", 0.0)),
    )
