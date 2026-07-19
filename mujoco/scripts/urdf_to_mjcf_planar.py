"""Compile a mech URDF → planar MJCF (MineWorld velocity control wrapper).

URDF supplies visual/collision geometry (F2/F5). MJCF adds POC planar joints
(slide_x / slide_y / yaw_z) + velocity actuators so Gateway MujocoMech works
unchanged. Wheels/casters are visual-only (no differential actuators).

Usage (repo root):
  .venv/bin/python mujoco/scripts/urdf_to_mjcf_planar.py --check
  .venv/bin/python mujoco/scripts/urdf_to_mjcf_planar.py \\
      --urdf mujoco/models/mechs/planar_cart.urdf \\
      --out mujoco/models/mechs/planar_cart.xml --check
"""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

MECHS = Path(__file__).resolve().parents[1] / "models" / "mechs"
DEFAULT_URDF = MECHS / "third_party" / "diffbot" / "diffbot.urdf"
DEFAULT_MJCF = MECHS / "diffbot_planar.xml"


def _parse_rgba(visual: ET.Element) -> str:
    """Return rgba string from URDF visual material, or a default."""
    mat = visual.find("material")
    if mat is None:
        return "0.55 0.58 0.62 1"
    color = mat.find("color")
    if color is None or not color.get("rgba"):
        return "0.55 0.58 0.62 1"
    return " ".join(color.get("rgba", "").split())


def _parse_box(visual: ET.Element) -> tuple[float, float, float] | None:
    """Return full-edge box size from URDF visual geometry, or None."""
    geom = visual.find("geometry")
    if geom is None:
        return None
    box = geom.find("box")
    if box is None or not box.get("size"):
        return None
    parts = [float(x) for x in box.get("size", "").split()]
    if len(parts) != 3:
        return None
    return parts[0], parts[1], parts[2]


def _parse_origin(elem: ET.Element | None) -> tuple[float, float, float]:
    """Return xyz from URDF origin, defaulting to origin."""
    if elem is None:
        return 0.0, 0.0, 0.0
    origin = elem.find("origin")
    if origin is None or not origin.get("xyz"):
        return 0.0, 0.0, 0.0
    parts = [float(x) for x in origin.get("xyz", "0 0 0").split()]
    while len(parts) < 3:
        parts.append(0.0)
    return parts[0], parts[1], parts[2]


def _parse_cylinder(visual: ET.Element) -> tuple[float, float] | None:
    """Return (radius, length) from URDF cylinder visual."""
    geom = visual.find("geometry")
    if geom is None:
        return None
    cyl = geom.find("cylinder")
    if cyl is None:
        return None
    return float(cyl.get("radius", "0.08")), float(cyl.get("length", "0.06"))


def _parse_sphere(visual: ET.Element) -> float | None:
    """Return sphere radius from URDF visual, or None."""
    geom = visual.find("geometry")
    if geom is None:
        return None
    sphere = geom.find("sphere")
    if sphere is None:
        return None
    return float(sphere.get("radius", "0.03"))


def _find_parent_joint(root: ET.Element, link_name: str) -> ET.Element | None:
    """Return the joint whose child is link_name."""
    for j in root.findall("joint"):
        child = j.find("child")
        if child is not None and child.get("link") == link_name:
            return j
    return None


def compile_urdf(urdf_path: Path) -> str:
    """Build MJCF XML string from URDF + POC planar actuators."""
    root = ET.parse(urdf_path).getroot()
    robot_name = root.get("name") or urdf_path.stem
    model_name = f"{robot_name}_planar"
    base = root.find("./link[@name='base_link']")
    if base is None:
        raise SystemExit("URDF missing link base_link")
    visual = base.find("visual")
    if visual is None:
        raise SystemExit("URDF base_link missing visual")
    box = _parse_box(visual)
    if box is None:
        raise SystemExit("URDF base_link visual must be a box")
    hx, hy, hz = box[0] / 2.0, box[1] / 2.0, box[2] / 2.0
    rgba = _parse_rgba(visual)
    mass_el = base.find("./inertial/mass")
    mass = float(mass_el.get("value", "10")) if mass_el is not None else 10.0
    # Chassis center height = full Z so wheel bottoms near z=0 for DiffBot layout.
    z0 = box[2]

    extra_geoms: list[str] = []
    for link in root.findall("link"):
        name = link.get("name", "")
        if name == "base_link":
            continue
        joint = _find_parent_joint(root, name)
        if joint is None:
            continue
        ox, oy, oz = _parse_origin(joint)
        wv = link.find("visual")
        if wv is None:
            continue
        rgba_v = _parse_rgba(wv)
        if "wheel" in name:
            cyl = _parse_cylinder(wv)
            if cyl is None:
                continue
            radius, length = cyl
            extra_geoms.append(
                f'      <geom name="{name}" type="cylinder" size="{radius} {length * 0.5}" '
                f'pos="{ox} {oy} {oz}" quat="0.7071 0.7071 0 0" '
                f'mass="0" contype="0" conaffinity="0" rgba="{rgba_v}"/>'
            )
            continue
        sphere_r = _parse_sphere(wv)
        if sphere_r is not None:
            extra_geoms.append(
                f'      <geom name="{name}" type="sphere" size="{sphere_r}" '
                f'pos="{ox} {oy} {oz}" mass="0" contype="0" conaffinity="0" '
                f'rgba="{rgba_v}"/>'
            )
            continue
        nb = _parse_box(wv)
        if nb is not None:
            nx, ny, nz = nb[0] / 2.0, nb[1] / 2.0, nb[2] / 2.0
            extra_geoms.append(
                f'      <geom name="{name}" type="box" size="{nx} {ny} {nz}" '
                f'pos="{ox} {oy} {oz}" mass="0" contype="0" conaffinity="0" '
                f'rgba="{rgba_v}"/>'
            )

    extras_block = "\n".join(extra_geoms)
    src = urdf_path.name
    return f"""<mujoco model="{model_name}">
  <!--
    AUTO-GENERATED from {src} by urdf_to_mjcf_planar.py — do not hand-edit;
    re-run the script. Planar free-plane joints + velocity servos are MineWorld
    POC control (same contract as box_mech / planar_cart).
  -->
  <option timestep="0.002" integrator="RK4" gravity="0 0 -9.81"/>

  <default>
    <geom contype="1" conaffinity="1" friction="0.8 0.02 0.01"/>
  </default>

  <worldbody>
    <body name="chassis" pos="0 0 {z0}">
      <joint name="slide_x" type="slide" axis="1 0 0" damping="0.2"/>
      <joint name="slide_y" type="slide" axis="0 1 0" damping="0.2"/>
      <joint name="yaw_z" type="hinge" axis="0 0 1" damping="0.05"/>
      <geom name="chassis_box" type="box" size="{hx} {hy} {hz}"
            mass="{mass}" rgba="{rgba}"/>
{extras_block}
    </body>
  </worldbody>

  <actuator>
    <velocity name="vx" joint="slide_x" kv="120" forcerange="-400 400" ctrlrange="-3 3"/>
    <velocity name="vy" joint="slide_y" kv="120" forcerange="-400 400" ctrlrange="-3 3"/>
    <velocity name="yaw_rate" joint="yaw_z" kv="60" forcerange="-200 200" ctrlrange="-6 6"/>
  </actuator>
</mujoco>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="URDF → planar MJCF wrapper")
    parser.add_argument("--urdf", type=Path, default=DEFAULT_URDF)
    parser.add_argument("--out", type=Path, default=DEFAULT_MJCF)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Load generated MJCF with mujoco after write",
    )
    args = parser.parse_args()
    xml = compile_urdf(args.urdf)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(xml, encoding="utf-8")
    print(f"wrote {args.out}")
    if args.check:
        import sys

        repo_root = Path(__file__).resolve().parents[2]
        sys.path = [p for p in sys.path if Path(p).resolve() != repo_root]
        import mujoco

        model = mujoco.MjModel.from_xml_path(str(args.out))
        print(
            f"mujoco OK nq={model.nq} nv={model.nv} nu={model.nu} "
            f"bodies={model.nbody}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
