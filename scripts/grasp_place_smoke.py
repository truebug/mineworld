"""IL: friction grasp prop_block → place on workbench (open gripper + AABB)."""

from __future__ import annotations

import sys
from pathlib import Path

import mujoco

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "gateway"))

from echo_server import (  # noqa: E402
    EchoGateway,
    Room,
    Session,
    _prop_touches_gripper,
    evaluate_objectives,
    load_contract,
)


def main() -> int:
    """Grasp → lift → seat on workbench → open; expect obj_place_block (+ lift)."""
    contract = load_contract(REPO / "examples" / "contracts" / "demo_workshop.json")
    gw = EchoGateway(
        contract,
        physics="mujoco",
        model_path=REPO / "mujoco" / "models" / "world_flat.xml",
        record_dir=None,
        contract_path=REPO / "examples" / "contracts" / "demo_workshop.json",
    )
    mechs, props, data, _sub, grasp_eq = gw._make_room_mechs(contract, gw.mj_model)
    if grasp_eq:
        print(f"FAIL: expected no grasp welds, got {grasp_eq}", file=sys.stderr)
        return 1
    mech = mechs["mech_player"]
    prop = props["prop_block"]
    room = Room(
        room_id="place_smoke",
        contract=contract,
        mechs=mechs,
        props=props,
        mj_data=data,
        grasp_eq=grasp_eq,
        mj_model=gw.mj_model,
    )
    session = Session(session_id="place_smoke", ws=None, contract=contract)  # type: ignore[arg-type]
    session.joined = True
    session.room = room
    session.controlled_entity_id = mech.entity_id
    mech.controlled = True

    # Reach + pinch (same seating trick as grasp_lift_smoke).
    for name, q in (("arm_yaw", 0.0), ("arm_shoulder", 1.4), ("arm_elbow", 0.0), ("gripper", 0.05)):
        mech._data.qpos[mech._pos_qadr[name]] = q
        mech.joint_targets[name] = q
    mujoco.mj_forward(mech._model, data)

    tip_id = mujoco.mj_name2id(mech._model, mujoco.mjtObj.mjOBJ_BODY, f"{mech.entity_id}/gripper_base")
    tip = data.xpos[tip_id]
    prop.reset_pose(
        {
            "x": float(tip[0]) + 0.06,
            "y": float(tip[1]),
            "z": float(tip[2]),
            "yaw": 0.0,
        }
    )
    mujoco.mj_forward(mech._model, data)

    mech.joint_targets["gripper"] = 0.0
    contacting = False
    for _ in range(80):
        mech.apply_ctrl()
        room.step_physics(0.02)
        prop.pull_state()
        if _prop_touches_gripper(mech._model, data, mech.entity_id, prop.entity_id):
            contacting = True
            break
    if not contacting:
        print("FAIL: gripper never contacted prop", file=sys.stderr)
        return 1

    mech.joint_targets["arm_shoulder"] = -0.2
    mech.joint_targets["arm_elbow"] = -0.8
    lifted = False
    for _ in range(200):
        mech.apply_ctrl()
        room.step_physics(0.02)
        prop.pull_state()
        events = evaluate_objectives(session)
        if any(e.get("objective_id") == "obj_lift_block" for e in events):
            lifted = True
            break
    if not lifted:
        print(f"FAIL: lift milestone missing (z={prop.z:.3f})", file=sys.stderr)
        return 1

    # Seat on workbench top (contract trigger_place / workbench at y=-8).
    prop.reset_pose({"x": 15.0, "y": -8.0, "z": 1.05, "yaw": 0.0})
    mech.joint_targets["gripper"] = 0.05
    mujoco.mj_forward(mech._model, data)
    for _ in range(40):
        mech.apply_ctrl()
        room.step_physics(0.02)
        prop.pull_state()
        events = evaluate_objectives(session)
        if any(e.get("objective_id") == "obj_place_block" for e in events):
            if session.outcome != "success":
                print("FAIL: place complete but outcome not success", file=sys.stderr)
                return 1
            print(f"grasp-place OK z={prop.z:.3f} outcome={session.outcome}")
            return 0

    print(
        f"FAIL: no place objective (prop=({prop.x:.2f},{prop.y:.2f},{prop.z:.3f}) "
        f"outcome={session.outcome})",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
