"""Compile MineWorld planar_cart.urdf → planar_cart.xml (MJCF).

F2 pilot: URDF holds visual/collision geometry; MJCF adds POC planar joints
(slide_x / slide_y / yaw_z) + velocity actuators so Gateway MujocoMech works
unchanged. Regenerates the checked-in MJCF next to the URDF.

Usage (repo root):
  .venv/bin/python mujoco/scripts/urdf_to_mjcf_planar.py
  .venv/bin/python mujoco/scripts/urdf_to_mjcf_planar.py --check  # load with mujoco
"""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

MECHS = Path(__file__).resolve().parents[1] / "models" / "mechs"
DEFAULT_URDF = MECHS / "planar_cart.urdf"
DEFAULT_MJCF = MECHS / "planar_cart.xml"


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


def compile_urdf(urdf_path: Path) -> str:
    """Build MJCF XML string from planar_cart URDF + POC planar actuators."""
    root = ET.parse(urdf_path).getroot()
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
    # Match box_mech: body pos z = full edge so bottom sits at half-extent above ground.
    z0 = box[2]

    wheel_geoms: list[str] = []
    for link in root.findall("link"):
        name = link.get("name", "")
        if not name.startswith("wheel_"):
            continue
        joint = None
        for j in root.findall("joint"):
            child = j.find("child")
            if child is not None and child.get("link") == name:
                joint = j
                break
        if joint is None:
            continue
        ox, oy, oz = _parse_origin(joint)
        wv = link.find("visual")
        cyl = _parse_cylinder(wv) if wv is not None else None
        if cyl is None:
            continue
        radius, length = cyl
        # URDF wheel visual uses rpy pitch=pi/2; MJCF cylinder axis is Z — rotate via quat.
        wheel_geoms.append(
            f'      <geom name="{name}" type="cylinder" size="{radius} {length * 0.5}" '
            f'pos="{ox} {oy} {oz}" quat="0.7071 0.7071 0 0" '
            f'mass="0" contype="0" conaffinity="0" rgba="0.15 0.15 0.18 1"/>'
        )

    nose_geom = ""
    nose_link = root.find("./link[@name='nose']")
    if nose_link is not None:
        jn = None
        for j in root.findall("joint"):
            child = j.find("child")
            if child is not None and child.get("link") == "nose":
                jn = j
                break
        ox, oy, oz = _parse_origin(jn)
        nv = nose_link.find("visual")
        nb = _parse_box(nv) if nv is not None else None
        if nb is not None:
            nx, ny, nz = nb[0] / 2.0, nb[1] / 2.0, nb[2] / 2.0
            nose_rgba = _parse_rgba(nv) if nv is not None else "0.85 0.2 0.15 1"
            nose_geom = (
                f'      <geom name="nose" type="box" size="{nx} {ny} {nz}" '
                f'pos="{ox} {oy} {oz}" mass="0" contype="0" conaffinity="0" '
                f'rgba="{nose_rgba}"/>'
            )

    wheels_block = "\n".join(wheel_geoms)
    return f"""<mujoco model="planar_cart">
  <!--
    AUTO-GENERATED from planar_cart.urdf by urdf_to_mjcf_planar.py — do not
    hand-edit; re-run the script. Planar free-plane joints + velocity servos
    are MineWorld POC control (same contract as box_mech).
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
            mass="10" rgba="{rgba}"/>
{nose_geom}
{wheels_block}
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
    parser = argparse.ArgumentParser(description="URDF → MJCF for planar_cart")
    parser.add_argument("--urdf", type=Path, default=DEFAULT_URDF)
    parser.add_argument("--out", type=Path, default=DEFAULT_MJCF)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Load generated MJCF with mujoco after write",
    )
    args = parser.parse_args()
    xml = compile_urdf(args.urdf)
    args.out.write_text(xml, encoding="utf-8")
    print(f"wrote {args.out}")
    if args.check:
        import sys

        # Repo folder `mujoco/` is a namespace package and shadows pip mujoco.
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
