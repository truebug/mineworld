#!/usr/bin/env python3
"""Generate a seed-stable city-block layout for demo_city.

Buildings (KayKit) sit on a grid; MuJoCo obstacles are the building footprints
(air walls). Streets between lots are drivible. Writes:

  examples/contracts/demo_city.json
  godot/spike/assets/kaykit_city/block_layout.json

Usage (repo root):
  .venv/bin/python scripts/gen_demo_city_block.py
  .venv/bin/python scripts/gen_demo_city_block.py --seed 7
"""

from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
CONTRACT_PATH = REPO / "examples" / "contracts" / "demo_city.json"
LAYOUT_PATH = REPO / "godot" / "spike" / "assets" / "kaykit_city" / "block_layout.json"

# Grid of lots (MW Z-up: +x east, +y north). Streets between lots are free.
COLS = 8
ROWS = 7
LOT = 5.0
STREET = 3.5
PITCH = LOT + STREET
OX = 0.0  # west edge of lot (0,0)
OY = -14.0  # south edge of lot (0,0)

BUILDING_ASSETS = [
    "building_A.gltf",
    "building_B.gltf",
    "building_C.gltf",
    "building_D.gltf",
    "building_E.gltf",
    "building_F.gltf",
    "building_G.gltf",
    "building_H.gltf",
]
# KayKit buildings: XZ AABB ≈ 2 m, origin-centered. scale = LOT/2 → dress = LOT.
MESH_XY = 2.0
BUILDING_SCALE = LOT / MESH_XY
# MuJoCo box must match dress footprint (was LOT-1 / LOT-0.5 → drive into mesh).
# Tiny margin so chassis bounces at the facade, not inside the glTF.
FOOTPRINT = MESH_XY * BUILDING_SCALE + 0.08
WALL_H = 3.5
HALF_PI = 1.57079632679
# Asphalt strips slightly narrower than street so lots read as sidewalk.
ROAD_WIDTH = STREET * 0.9
CITY_SPAWN_COUNT = 5


def _bounds() -> tuple[float, float, float, float]:
    """Return (min_x, max_x, min_y, max_y) of the outer curb inner face."""
    min_x = OX - STREET
    max_x = OX + (COLS - 1) * PITCH + LOT + STREET
    min_y = OY - STREET
    max_y = OY + (ROWS - 1) * PITCH + LOT + STREET
    return min_x, max_x, min_y, max_y


def _lot_center(col: int, row: int) -> tuple[float, float]:
    """Return MW (x, y) center of lot (col, row)."""
    return OX + col * PITCH + LOT * 0.5, OY + row * PITCH + LOT * 0.5


def _street_centers() -> tuple[list[float], list[float]]:
    """N-S and E-W street centerlines (MW x / y)."""
    xs = [OX - STREET * 0.5]
    for col in range(COLS):
        xs.append(OX + col * PITCH + LOT + STREET * 0.5)
    ys = [OY - STREET * 0.5]
    for row in range(ROWS):
        ys.append(OY + row * PITCH + LOT + STREET * 0.5)
    return xs, ys


def _build_roads() -> list[dict[str, Any]]:
    """Plain asphalt strips along street corridors (no KayKit lane textures)."""
    min_x, max_x, min_y, max_y = _bounds()
    street_xs, street_ys = _street_centers()
    span_x = max_x - min_x
    span_y = max_y - min_y
    mid_x = (min_x + max_x) * 0.5
    mid_y = (min_y + max_y) * 0.5
    roads: list[dict[str, Any]] = []
    rid = 0

    # E-W corridors (full block length).
    for sy in street_ys:
        roads.append(
            {
                "id": f"road_{rid}",
                "kind": "strip",
                "x": round(mid_x, 3),
                "y": round(sy, 3),
                "sx": round(span_x + STREET * 0.2, 3),
                "sy": round(ROAD_WIDTH, 3),
            }
        )
        rid += 1

    # N-S corridors (full block length).
    for sx in street_xs:
        roads.append(
            {
                "id": f"road_{rid}",
                "kind": "strip",
                "x": round(sx, 3),
                "y": round(mid_y, 3),
                "sx": round(ROAD_WIDTH, 3),
                "sy": round(span_y + STREET * 0.2, 3),
            }
        )
        rid += 1

    return roads


def _build_street_props(rng: random.Random, buildings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """KayKit sidewalk props near buildings (viewer_only)."""
    assets = [
        "streetlight.gltf",
        "bench.gltf",
        "bush.gltf",
        "firehydrant.gltf",
        "dumpster.gltf",
    ]
    props: list[dict[str, Any]] = []
    for b in buildings:
        if rng.random() > 0.42:
            continue
        # Offset toward nearest street: random cardinal, ~lot edge.
        angle = rng.choice([0.0, HALF_PI, 3.14159265359, -HALF_PI])
        dist = (LOT - 1.0) * 0.5 + 0.35
        px = float(b["x"]) + math.cos(angle) * dist
        py = float(b["y"]) + math.sin(angle) * dist
        asset = rng.choice(assets)
        scale = 1.0 if asset != "bush.gltf" else rng.choice([0.8, 1.0, 1.2])
        props.append(
            {
                "id": f"decor_{len(props)}",
                "asset": asset,
                "x": round(px, 3),
                "y": round(py, 3),
                "yaw": angle + HALF_PI,
                "scale": scale,
            }
        )
    return props


def build_layout(seed: int) -> dict[str, Any]:
    """Build layout dict: buildings + roads + props + spawn/finish hints."""
    rng = random.Random(seed)
    min_x, max_x, min_y, max_y = _bounds()
    buildings: list[dict[str, Any]] = []
    obstacles: list[dict[str, Any]] = []

    for row in range(ROWS):
        for col in range(COLS):
            # Leave one plaza lot empty near the finish approach (east mid).
            if col == COLS - 1 and row == ROWS // 2:
                continue
            # Sparse random holes (~15%) for variety, keep perimeter denser.
            if col not in (0, COLS - 1) and row not in (0, ROWS - 1):
                if rng.random() < 0.15:
                    continue
            cx, cy = _lot_center(col, row)
            asset = rng.choice(BUILDING_ASSETS)
            yaw = rng.choice([0.0, HALF_PI, 3.14159265359, -HALF_PI])
            bid = f"bldg_{col}_{row}"
            buildings.append(
                {
                    "id": bid,
                    "asset": asset,
                    "x": round(cx, 3),
                    "y": round(cy, 3),
                    "yaw": yaw,
                    "scale": BUILDING_SCALE,
                    "footprint": [FOOTPRINT, FOOTPRINT],
                }
            )
            obstacles.append(
                {
                    "id": bid,
                    "shape": "box",
                    "size": [FOOTPRINT, FOOTPRINT, WALL_H],
                    "pose": {
                        "x": round(cx, 3),
                        "y": round(cy, 3),
                        "z": WALL_H * 0.5,
                        "yaw": 0.0,
                    },
                    "physics_role": "mujoco_authoritative",
                }
            )

    # Outer air-wall curb (thin boxes).
    mid_x = (min_x + max_x) * 0.5
    mid_y = (min_y + max_y) * 0.5
    span_x = max_x - min_x
    span_y = max_y - min_y
    curb = 0.5
    obstacles.extend(
        [
            {
                "id": "boundary_n",
                "shape": "box",
                "size": [span_x + curb, curb, WALL_H],
                "pose": {"x": mid_x, "y": max_y, "z": WALL_H * 0.5, "yaw": 0.0},
                "physics_role": "mujoco_authoritative",
            },
            {
                "id": "boundary_s",
                "shape": "box",
                "size": [span_x + curb, curb, WALL_H],
                "pose": {"x": mid_x, "y": min_y, "z": WALL_H * 0.5, "yaw": 0.0},
                "physics_role": "mujoco_authoritative",
            },
            {
                "id": "boundary_w",
                "shape": "box",
                "size": [curb, span_y + curb, WALL_H],
                "pose": {"x": min_x, "y": mid_y, "z": WALL_H * 0.5, "yaw": 0.0},
                "physics_role": "mujoco_authoritative",
            },
            {
                "id": "boundary_e",
                "shape": "box",
                "size": [curb, span_y + curb, WALL_H],
                "pose": {"x": max_x, "y": mid_y, "z": WALL_H * 0.5, "yaw": 0.0},
                "physics_role": "mujoco_authoritative",
            },
        ]
    )

    # Spawn SW street; finish NE street — Manhattan path needs a turn.
    street_xs, street_ys = _street_centers()
    spawn_x = street_xs[0]
    spawn_y = street_ys[1]  # first E-W corridor (between lot rows 0–1)
    finish_x = street_xs[-1]
    finish_y = street_ys[-2]  # last E-W corridor (not the outer curb)
    # Crate on a side street (not the SW→NE main path) so reach is not blocked.
    crate_x = street_xs[2]
    crate_y = street_ys[3]

    return {
        "seed": seed,
        "frame": "mineworld_zup_m",
        "bounds": {
            "min_x": round(min_x, 3),
            "max_x": round(max_x, 3),
            "min_y": round(min_y, 3),
            "max_y": round(max_y, 3),
        },
        "spawn": {"x": round(spawn_x, 3), "y": round(spawn_y, 3)},
        "finish": {
            "x": round(finish_x, 3),
            "y": round(finish_y, 3),
            "half_x": 2.0,
            "half_y": 1.8,
        },
        "crate": {"x": round(crate_x, 3), "y": round(crate_y, 3)},
        "buildings": buildings,
        "props": _build_street_props(rng, buildings),
        "roads": _build_roads(),
        "obstacles": obstacles,
        "ground": {
            "cx": round(mid_x, 3),
            "cy": round(mid_y, 3),
            "sx": round(span_x + 8.0, 3),
            "sy": round(span_y + 8.0, 3),
            # Light sidewalk base under lots; asphalt strips overlay streets.
            "color": [0.62, 0.64, 0.66, 1.0],
        },
    }


def write_contract(layout: dict[str, Any]) -> None:
    """Rewrite demo_city.json from layout (keep protocol shape)."""
    sp = layout["spawn"]
    fin = layout["finish"]
    cr = layout["crate"]
    spawns: list[dict[str, Any]] = []
    for i in range(CITY_SPAWN_COUNT):
        sid = "mech_player" if i == 0 else f"mech_player_{chr(ord('b') + i - 1)}"
        spawns.append(
            {
                "id": sid,
                "model_ref": "mechs/diffbot_planar.xml",
                "pose": {
                    # Park along west N-S street (north of corridor) so lane stays clear.
                    "x": sp["x"],
                    "y": round(sp["y"] + 1.35 * i, 3),
                    "z": 0.5,
                    "yaw": 0.0,
                },
                "player_slot": i,
                "control_mode": "velocity",
                "physics_role": "mujoco_authoritative",
            }
        )
    contract: dict[str, Any] = {
        "contract_version": "0.1",
        "level_id": "demo_city",
        "seed": layout["seed"],
        "frame": "mineworld_zup_m",
        "sim": {"dt": 0.02},
        "mech_spawns": spawns,
        "dynamic_props": [
            {
                "id": "prop_crate",
                "kind": "dynamic_prop",
                "shape": "box",
                "size": [0.5, 0.5, 0.5],
                "pose": {"x": cr["x"], "y": cr["y"], "z": 0.25, "yaw": 0.0},
                "mass": 1.2,
                "physics_role": "mujoco_authoritative",
            }
        ],
        "static_obstacles": layout["obstacles"],
        "objectives": [
            {
                "id": "obj_reach_zone",
                "type": "reach_region",
                "target": "trigger_finish",
                "description": "街区街道：绕行至东北角终点绿区",
            }
        ],
        "triggers": [
            {
                "id": "trigger_finish",
                "type": "aabb",
                "min": [
                    round(fin["x"] - fin["half_x"], 3),
                    round(fin["y"] - fin["half_y"], 3),
                    0.0,
                ],
                "max": [
                    round(fin["x"] + fin["half_x"], 3),
                    round(fin["y"] + fin["half_y"], 3),
                    2.0,
                ],
            }
        ],
        "tags": ["poc", "demo", "city", "block", "air_walls"],
        "extensions": {
            "mw": {
                "default_room_id": "city",
                "max_members": CITY_SPAWN_COUNT,
            },
            "mw.editor": {
                "client_scene": "res://demo_city.tscn",
                "exported_from": "scripts/gen_demo_city_block.py",
                "layout": "res://assets/kaykit_city/block_layout.json",
                "notes": "Buildings=viewer_only; footprints≈LOT align MuJoCo air walls; spawn SW → finish NE.",
            },
        },
    }
    CONTRACT_PATH.write_text(json.dumps(contract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def godot_layout_view(layout: dict[str, Any]) -> dict[str, Any]:
    """Strip MuJoCo obstacles; keep viewer dress fields."""
    return {
        "seed": layout["seed"],
        "bounds": layout["bounds"],
        "spawn": layout["spawn"],
        "finish": layout["finish"],
        "crate": layout["crate"],
        "ground": layout["ground"],
        "buildings": layout["buildings"],
        "props": layout.get("props") or [],
        "roads": layout.get("roads") or [],
    }


def generate_and_write(seed: int) -> dict[str, Any]:
    """Build layout, write contract + block_layout.json, return summary."""
    layout = build_layout(seed)
    godot_layout = godot_layout_view(layout)
    LAYOUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    LAYOUT_PATH.write_text(
        json.dumps(godot_layout, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_contract(layout)
    return {
        "seed": seed,
        "buildings": len(layout["buildings"]),
        "props": len(godot_layout["props"]),
        "roads": len(godot_layout["roads"]),
        "obstacles": len(layout["obstacles"]),
        "bounds": layout["bounds"],
        "contract": str(CONTRACT_PATH.relative_to(REPO)),
        "layout": str(LAYOUT_PATH.relative_to(REPO)),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate demo_city city-block layout")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    summary = generate_and_write(args.seed)
    print(
        f"OK seed={summary['seed']} buildings={summary['buildings']} "
        f"props={summary.get('props', '?')} roads={summary['roads']} "
        f"obstacles={summary['obstacles']}"
    )
    print(f"  contract → {summary['contract']}")
    print(f"  layout   → {summary['layout']}")
    b = summary["bounds"]
    print(
        f"  bounds MW x=[{b['min_x']},{b['max_x']}] y=[{b['min_y']},{b['max_y']}]"
    )


if __name__ == "__main__":
    main()
