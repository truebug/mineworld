"""Export MineWorld scene contract fragments from a Godot .tscn (F4 / T4.2).

Reads nodes tagged with metadata `contract_kind` and merges into a base
contract JSON. Godot Y-up → MineWorld Z-up:

  mw = (godot.x, -godot.z, godot.y)
  size_mw = (size.x, size.z, size.y)   # BoxMesh full edges
  yaw_mw = rotation.y (radians)

Usage (repo root):
  .venv/bin/python scripts/export_scene_contract.py
  .venv/bin/python scripts/export_scene_contract.py --check   # write temp + compare
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
DEFAULT_SCENE = REPO / "godot" / "spike" / "main.tscn"
DEFAULT_BASE = REPO / "examples" / "contracts" / "tutorial_01.json"

NODE_RE = re.compile(
    r'^\[node name="([^"]+)"(?: type="([^"]*)")?(?: parent="([^"]*)")?.*\]\s*$'
)
SUBRES_RE = re.compile(r'^\[sub_resource type="([^"]+)" id="([^"]+)"\]\s*$')
TRANSFORM_RE = re.compile(
    r"^transform = Transform3D\("
    r"([^)]+)\)\s*$"
)
META_RE = re.compile(r'^metadata/(\w+)\s*=\s*(.+)\s*$')
MESH_RE = re.compile(r'^mesh = SubResource\("([^"]+)"\)\s*$')
PROP_RE = re.compile(r'^(\w+)\s*=\s*(.+)\s*$')


def _godot_unquote(raw: str) -> str:
    """Strip Godot string quotes."""
    s = raw.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1]
    return s


def _parse_transform(line: str) -> tuple[tuple[float, float, float], float] | None:
    """Return ((ox,oy,oz), yaw_y) from a Transform3D line, or None."""
    m = TRANSFORM_RE.match(line.strip())
    if not m:
        return None
    parts = [float(x.strip()) for x in m.group(1).split(",")]
    if len(parts) != 12:
        return None
    # basis row-major 3x3 then origin
    bx0, bx1, bx2, by0, by1, by2, bz0, bz1, bz2, ox, oy, oz = parts
    # yaw about Godot Y ≈ atan2(-bz0?); for pure Y rotation basis is
    # [c 0 s; 0 1 0; -s 0 c] in column form — Godot stores columns:
    # col0=(c,0,-s), col1=(0,1,0), col2=(s,0,c) → flat: c,0,-s, 0,1,0, s,0,c
    yaw = math.atan2(bz0, bx0) if abs(bx0) + abs(bz0) > 1e-9 else 0.0
    # Prefer atan2(basis.x.z, basis.x.x) = atan2(s, c) with col2.x=s, col0.x=c
    yaw = math.atan2(parts[6], parts[0])
    return (ox, oy, oz), yaw


def _godot_pos_to_mw(ox: float, oy: float, oz: float) -> dict[str, float]:
    """Godot (x,y,z) → MW pose x,y,z (yaw filled by caller)."""
    return {"x": ox, "y": -oz, "z": oy}


def _godot_size_to_mw(sx: float, sy: float, sz: float) -> list[float]:
    """Godot BoxMesh size → MW full-edge [x,y,z]."""
    return [sx, sz, sy]


def parse_tscn(text: str) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    """Parse sub_resources and nodes from .tscn text."""
    subres: dict[str, dict[str, Any]] = {}
    nodes: list[dict[str, Any]] = []
    lines = text.splitlines()
    i = 0
    current: dict[str, Any] | None = None
    mode: str | None = None

    def flush() -> None:
        nonlocal current, mode
        if mode == "sub" and current is not None:
            subres[current["id"]] = current
        elif mode == "node" and current is not None:
            nodes.append(current)
        current = None
        mode = None

    while i < len(lines):
        line = lines[i]
        if line.startswith("["):
            flush()
            sm = SUBRES_RE.match(line)
            nm = NODE_RE.match(line)
            if sm:
                mode = "sub"
                current = {"type": sm.group(1), "id": sm.group(2), "props": {}}
            elif nm:
                mode = "node"
                current = {
                    "name": nm.group(1),
                    "type": nm.group(2) or "",
                    "parent": nm.group(3) or "",
                    "props": {},
                    "meta": {},
                }
            else:
                mode = None
                current = None
            i += 1
            continue
        if current is None:
            i += 1
            continue
        mm = META_RE.match(line)
        if mm and mode == "node":
            key = mm.group(1)
            val = mm.group(2).strip()
            if val.startswith('"'):
                current["meta"][key] = _godot_unquote(val)
            elif val in ("true", "false"):
                current["meta"][key] = val == "true"
            else:
                try:
                    current["meta"][key] = int(val) if "." not in val else float(val)
                except ValueError:
                    current["meta"][key] = val
            i += 1
            continue
        tr = _parse_transform(line)
        if tr and mode == "node":
            current["origin"], current["yaw"] = tr
            i += 1
            continue
        mesh_m = MESH_RE.match(line)
        if mesh_m and mode == "node":
            current["mesh_id"] = mesh_m.group(1)
            i += 1
            continue
        pm = PROP_RE.match(line)
        if pm and mode == "sub":
            key, raw = pm.group(1), pm.group(2).strip()
            if key == "size" and "Vector3" in raw:
                inner = re.search(r"Vector3\(([^)]+)\)", raw)
                if inner:
                    current["props"]["size"] = [
                        float(x.strip()) for x in inner.group(1).split(",")
                    ]
            elif key == "size" and "Vector2" in raw:
                inner = re.search(r"Vector2\(([^)]+)\)", raw)
                if inner:
                    current["props"]["size"] = [
                        float(x.strip()) for x in inner.group(1).split(",")
                    ]
            else:
                current["props"][key] = raw
            i += 1
            continue
        i += 1
    flush()
    return subres, nodes


def _node_path(node: dict[str, Any]) -> str:
    """Build approximate path for parent checks."""
    parent = node.get("parent") or ""
    name = node["name"]
    if parent in ("", "."):
        return name
    return f"{parent}/{name}"


def export_from_scene(
    scene_path: Path,
    base: dict[str, Any],
) -> dict[str, Any]:
    """Merge tagged scene nodes into a copy of base contract."""
    subres, nodes = parse_tscn(scene_path.read_text(encoding="utf-8"))
    out = json.loads(json.dumps(base))  # deep copy
    obstacles: list[dict[str, Any]] = []
    triggers: list[dict[str, Any]] = []
    spawns: list[dict[str, Any]] = []
    viewer_props: list[dict[str, Any]] = []

    # Skip children of viewer_only parents.
    viewer_parents: set[str] = set()
    for n in nodes:
        role = str(n.get("meta", {}).get("physics_role", ""))
        if role == "viewer_only":
            viewer_parents.add(n["name"])
            viewer_parents.add(_node_path(n))

    for n in nodes:
        parent = n.get("parent") or ""
        if parent in viewer_parents or parent.startswith("Decor"):
            # Decor subtree: optional listing only
            if n.get("meta", {}).get("contract_kind") == "viewer_prop":
                ox, oy, oz = n.get("origin", (0.0, 0.0, 0.0))
                pose = _godot_pos_to_mw(ox, oy, oz)
                pose["yaw"] = float(n.get("yaw", 0.0))
                viewer_props.append(
                    {
                        "id": n["meta"].get("mujoco_entity_id", n["name"]),
                        "pose": pose,
                        "physics_role": "viewer_only",
                    }
                )
            continue

        kind = str(n.get("meta", {}).get("contract_kind", ""))
        if not kind:
            continue
        eid = str(n["meta"].get("mujoco_entity_id", n["name"]))
        ox, oy, oz = n.get("origin", (0.0, 0.0, 0.0))
        yaw = float(n.get("yaw", 0.0))
        pose = _godot_pos_to_mw(ox, oy, oz)
        pose["yaw"] = yaw

        if kind == "static_obstacle":
            mesh_id = n.get("mesh_id")
            size_g = (subres.get(mesh_id) or {}).get("props", {}).get("size") or [1, 1, 1]
            if len(size_g) < 3:
                size_g = list(size_g) + [1.0] * (3 - len(size_g))
            obstacles.append(
                {
                    "id": eid,
                    "shape": "box",
                    "size": _godot_size_to_mw(float(size_g[0]), float(size_g[1]), float(size_g[2])),
                    "pose": pose,
                    "physics_role": str(
                        n["meta"].get("physics_role", "mujoco_authoritative")
                    ),
                }
            )
        elif kind == "trigger_aabb":
            mesh_id = n.get("mesh_id")
            size_g = (subres.get(mesh_id) or {}).get("props", {}).get("size") or [2, 2, 2]
            sx, sy, sz = float(size_g[0]), float(size_g[1]), float(size_g[2])
            # MW half-extents from Godot box centered at pose
            hx, hy, hz = sx / 2.0, sz / 2.0, sy / 2.0
            cx, cy, cz = pose["x"], pose["y"], pose["z"]
            triggers.append(
                {
                    "id": eid,
                    "type": "aabb",
                    "min": [cx - hx, cy - hy, cz - hz],
                    "max": [cx + hx, cy + hy, cz + hz],
                }
            )
        elif kind == "mech_spawn":
            slot = int(n["meta"].get("player_slot", len(spawns)))
            model_ref = str(n["meta"].get("model_ref", "mechs/planar_cart.xml"))
            spawns.append(
                {
                    "id": eid,
                    "model_ref": model_ref,
                    "pose": {
                        "x": pose["x"],
                        "y": pose["y"],
                        "z": float(n["meta"].get("spawn_z", pose["z"] if pose["z"] else 0.5)),
                        "yaw": yaw,
                    },
                    "player_slot": slot,
                    "control_mode": "velocity",
                    "physics_role": "mujoco_authoritative",
                }
            )

    if obstacles:
        out["static_obstacles"] = obstacles
    if triggers:
        out["triggers"] = triggers
        # Keep objectives pointing at first trigger if present
        if out.get("objectives") and triggers:
            out["objectives"][0]["target"] = triggers[0]["id"]
    if spawns:
        # Preserve extra spawns from base not present in scene (e.g. player B).
        by_id = {s["id"]: s for s in spawns}
        merged = list(spawns)
        for s in base.get("mech_spawns") or []:
            if s.get("id") not in by_id:
                merged.append(s)
        merged.sort(key=lambda s: int(s.get("player_slot", 0)))
        out["mech_spawns"] = merged
    if viewer_props:
        ext = out.setdefault("extensions", {})
        mw = ext.setdefault("mw", {})
        mw["viewer_props"] = viewer_props
        mw["exported_from"] = str(scene_path.resolve().relative_to(REPO)).replace("\\", "/")
    else:
        ext = out.setdefault("extensions", {})
        mw = ext.setdefault("mw", {})
        mw["exported_from"] = str(scene_path.resolve().relative_to(REPO)).replace("\\", "/")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Export scene contract from .tscn")
    parser.add_argument("--scene", type=Path, default=DEFAULT_SCENE)
    parser.add_argument("--base", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--out", type=Path, default=None, help="Default: overwrite --base")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Export to stdout summary; exit 1 if obstacles/triggers differ from base",
    )
    args = parser.parse_args()
    base = json.loads(args.base.read_text(encoding="utf-8"))
    exported = export_from_scene(args.scene, base)
    out_path = args.out or args.base

    if args.check:
        bo = base.get("static_obstacles") or []
        eo = exported.get("static_obstacles") or []
        bt = base.get("triggers") or []
        et = exported.get("triggers") or []
        print(f"scene={args.scene}")
        print(f"obstacles base={len(bo)} export={len(eo)} {eo}")
        print(f"triggers   base={len(bt)} export={len(et)} {et}")
        print(f"spawns     export={len(exported.get('mech_spawns') or [])}")
        # Soft check: wall pose/size should match
        if bo and eo:
            if bo[0].get("pose") != eo[0].get("pose") or bo[0].get("size") != eo[0].get("size"):
                print("DIFF: static_obstacles[0] changed vs base")
                print("  base", bo[0])
                print("  export", eo[0])
                return 1
        if bt and et:
            if bt[0].get("min") != et[0].get("min") or bt[0].get("max") != et[0].get("max"):
                print("DIFF: triggers[0] changed vs base")
                print("  base", bt[0])
                print("  export", et[0])
                return 1
        print("check OK")
        return 0

    out_path.write_text(json.dumps(exported, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
