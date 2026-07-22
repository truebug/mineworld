#!/usr/bin/env python3
"""Generate a long curved demo_race track (MuJoCo walls + gentle ramps + layout).

Race chassis v3 is Ackermann (steer + RWD) on freejoint contact wheels.
Godot dress remains viewer-only.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CONTRACT = REPO / "examples" / "contracts" / "demo_race.json"
LAYOUT = REPO / "godot" / "spike" / "data" / "race_layout.json"
MODEL_REF = "mechs/diffbot_race_v3.xml"

# Wide multi-lobe circuit (~750 m lap; wheel-torque tops ~15–20 m/s).
SEMI_A = 110.0
SEMI_B = 72.0
LANE_HALF = 8.5
WALL_THICK = 0.9
WALL_H = 1.6
SEGMENTS = 120
SPAWN_COUNT = 6
SPAWN_SPACE_M = 3.6
SPAWN_BACK_M = 5.0
SPAWN_ROW_GAP_M = 3.8
SPAWN_Z = 0.28
RAMP_FRICTION = 1.6


def _centerline(n: int) -> list[tuple[float, float]]:
    """Closed 3-lobe elongated circuit (more corners / longer lap)."""
    pts: list[tuple[float, float]] = []
    for i in range(n):
        t = 2.0 * math.pi * i / n
        lobe = 1.0 + 0.38 * math.cos(3.0 * t) + 0.1 * math.cos(6.0 * t + 0.5)
        x = SEMI_A * lobe * math.cos(t)
        y = SEMI_B * lobe * math.sin(t)
        pts.append((x, y))
    return pts


def _wall_boxes(
    pts: list[tuple[float, float]], *, inner: bool
) -> list[dict]:
    """Box segments offset left/right of centerline."""
    n = len(pts)
    out: list[dict] = []
    side = -1.0 if inner else 1.0
    offset = LANE_HALF + WALL_THICK * 0.5
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        if length < 0.4:
            continue
        tx, ty = dx / length, dy / length
        nx, ny = -ty, tx
        mx = 0.5 * (x0 + x1) + side * offset * nx
        my = 0.5 * (y0 + y1) + side * offset * ny
        yaw = math.atan2(ty, tx)
        tag = "in" if inner else "out"
        out.append(
            {
                "id": f"wall_{tag}_{i:03d}",
                "shape": "box",
                "size": [length + 0.15, WALL_THICK, WALL_H],
                "pose": {
                    "x": round(mx, 3),
                    "y": round(my, 3),
                    "z": round(WALL_H * 0.5, 3),
                    "yaw": round(yaw, 4),
                },
                # Low friction so contact wheels glance instead of welding to walls.
                "friction": 0.2,
                "physics_role": "mujoco_authoritative",
            }
        )
    return out


def _ramp_boxes(
    pts: list[tuple[float, float]], indices: list[int]
) -> list[dict]:
    """Gentle stepped ramps along centerline (climbable by contact wheels)."""
    n = len(pts)
    boxes: list[dict] = []
    # Three steps then a short plateau; half-sizes in meters.
    steps = [
        (3.5, 6.5, 0.04, 0.04),
        (3.5, 6.5, 0.04, 0.08),
        (3.5, 6.5, 0.04, 0.12),
        (5.0, 6.5, 0.04, 0.12),
    ]
    for ri, idx in enumerate(indices):
        x0, y0 = pts[idx % n]
        x1, y1 = pts[(idx + 1) % n]
        yaw = math.atan2(y1 - y0, x1 - x0)
        c, s = math.cos(yaw), math.sin(yaw)
        # Offset to inner half-lane so centerline chase stays clear.
        nx, ny = -s, c
        along = 0.0
        for si, (hx, hy, hz, z_top) in enumerate(steps):
            cx = x0 + c * (along + hx) + nx * (LANE_HALF * 0.55)
            cy = y0 + s * (along + hx) + ny * (LANE_HALF * 0.55)
            boxes.append(
                {
                    "id": f"ramp_{ri}_{si}",
                    "shape": "box",
                    "size": [hx * 2.0, hy * 2.0, hz * 2.0],
                    "pose": {
                        "x": round(cx, 3),
                        "y": round(cy, 3),
                        "z": round(z_top, 3),
                        "yaw": round(yaw, 4),
                    },
                    "friction": RAMP_FRICTION,
                    "physics_role": "mujoco_authoritative",
                }
            )
            along += hx * 2.0
    return boxes


def _aabb_at(pt: tuple[float, float], half: float = 4.0) -> dict:
    """Axis-aligned trigger around a centerline point."""
    x, y = pt
    return {
        "min": [round(x - half, 2), round(y - half, 2), 0.0],
        "max": [round(x + half, 2), round(y + half, 2), 2.5],
    }


def build() -> tuple[dict, dict]:
    """Return (contract, layout)."""
    pts = _centerline(SEGMENTS)
    # Start near south (t≈3π/2 → index).
    start_i = int(SEGMENTS * 0.75) % SEGMENTS
    # Checkpoints at ~⅓ / ⅔ lap; finish just before start (force almost full lap).
    cp1_i = (start_i + SEGMENTS // 3) % SEGMENTS
    cp2_i = (start_i + 2 * SEGMENTS // 3) % SEGMENTS
    fin_i = (start_i + SEGMENTS - 3) % SEGMENTS
    # Ramps mid-straight-ish: offset from CPs so smoke chase still clear.
    ramp_is = [
        (start_i + SEGMENTS // 6) % SEGMENTS,
        (cp1_i + SEGMENTS // 8) % SEGMENTS,
    ]
    walls = _wall_boxes(pts, inner=False) + _wall_boxes(pts, inner=True)
    # Optional climb pads (offset off centerline). Disabled for v3 ship —
    # Ackermann + wall contact first; re-enable when chase/unstick is solid.
    # walls += _ramp_boxes(pts, ramp_is)

    x0, y0 = pts[start_i]
    x1, y1 = pts[(start_i + 1) % SEGMENTS]
    yaw0 = math.atan2(y1 - y0, x1 - x0)
    # Start grid: stack perpendicular to tangent (inward).
    tx, ty = math.cos(yaw0), math.sin(yaw0)
    nx, ny = -ty, tx
    spawns = []
    for i in range(SPAWN_COUNT):
        sid = "mech_player" if i == 0 else f"mech_player_{chr(ord('b') + i - 1)}"
        # 2×3 grid behind the line, inside the lane (not outside the outer wall).
        row = i // 3
        col = i % 3
        back = SPAWN_BACK_M + row * SPAWN_ROW_GAP_M
        lateral = (col - 1) * SPAWN_SPACE_M
        sx = x0 - tx * back + nx * lateral
        sy = y0 - ty * back + ny * lateral
        spawns.append(
            {
                "id": sid,
                "model_ref": MODEL_REF,
                "pose": {
                    "x": round(sx, 3),
                    "y": round(sy, 3),
                    "z": SPAWN_Z,
                    "yaw": round(yaw0, 4),
                },
                "player_slot": i,
                "control_mode": "velocity",
                "physics_role": "mujoco_authoritative",
            }
        )

    trig_cp1 = {"id": "trigger_cp1", "type": "aabb", **_aabb_at(pts[cp1_i], 8.0)}
    trig_cp2 = {"id": "trigger_cp2", "type": "aabb", **_aabb_at(pts[cp2_i], 8.0)}
    trig_fin = {"id": "trigger_finish", "type": "aabb", **_aabb_at(pts[fin_i], 8.5)}

    contract = {
        "contract_version": "0.1",
        "level_id": "demo_race",
        "seed": 2,
        "frame": "mineworld_zup_m",
        "sim": {"dt": 0.02},
        "mech_spawns": spawns,
        "dynamic_props": [],
        "static_obstacles": walls,
        "objectives": [
            {
                "id": "obj_cp1",
                "type": "reach_region",
                "target": "trigger_cp1",
                "description": "Checkpoint 1",
                "params": {"terminal": False},
            },
            {
                "id": "obj_cp2",
                "type": "reach_region",
                "target": "trigger_cp2",
                "description": "Checkpoint 2",
                "params": {"terminal": False, "requires": ["obj_cp1"]},
            },
            {
                "id": "obj_race_finish",
                "type": "reach_region",
                "target": "trigger_finish",
                "description": "Finish after nearly full lap",
                "params": {"terminal": True, "requires": ["obj_cp1", "obj_cp2"]},
            },
        ],
        "triggers": [trig_cp1, trig_cp2, trig_fin],
        "tags": ["race", "timed", "shared_ffa", "mujoco", "long_circuit"],
        "extensions": {
            "mw": {
                "default_room_id": "race",
                "max_members": 6,
                "mode": "shared_ffa",
            },
            "mw.il": {
                "task_id": "obj_race_finish",
                "time_limit_s": 400,
            },
            "mw.editor": {
                "client_scene": "res://demo_race.tscn",
                "layout": "res://data/race_layout.json",
            },
        },
    }

    # Approx lap length.
    lap = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        lap += math.hypot(x1 - x0, y1 - y0)

    layout = {
        "level_id": "demo_race",
        "lap_m": round(lap, 1),
        "lane_half_m": LANE_HALF,
        "centerline": [{"x": round(x, 2), "y": round(y, 2)} for x, y in pts],
        "walls": walls,
        "triggers": [
            {"id": t["id"], "min": t["min"], "max": t["max"]}
            for t in (trig_cp1, trig_cp2, trig_fin)
        ],
        "start_index": start_i,
        "finish_index": fin_i,
    }
    return contract, layout


def main() -> None:
    """Write contract + Godot layout."""
    contract, layout = build()
    CONTRACT.parent.mkdir(parents=True, exist_ok=True)
    LAYOUT.parent.mkdir(parents=True, exist_ok=True)
    CONTRACT.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")
    LAYOUT.write_text(json.dumps(layout, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {CONTRACT.relative_to(REPO)} walls={len(contract['static_obstacles'])} "
        f"lap≈{layout['lap_m']}m"
    )
    print(f"wrote {LAYOUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
