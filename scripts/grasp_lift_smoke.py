"""V3c: sticky grasp + lift prop_crate above min_z (offline MuJoCo, no WS)."""

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
    evaluate_objectives,
    load_contract,
)


def main() -> int:
    """Place crate near gripper, close (sticky weld), lift; expect obj_lift_crate."""
    contract = load_contract(REPO / "examples" / "contracts" / "demo_workshop.json")
    gw = EchoGateway(
        contract,
        physics="mujoco",
        model_path=REPO / "mujoco" / "models" / "world_flat.xml",
        record_dir=None,
        contract_path=REPO / "examples" / "contracts" / "demo_workshop.json",
    )
    mechs, props, data, _sub, grasp_eq = gw._make_room_mechs(contract, gw.mj_model)
    mech = mechs["mech_player"]
    prop = props["prop_crate"]
    room = Room(
        room_id="grasp_smoke",
        contract=contract,
        mechs=mechs,
        props=props,
        mj_data=data,
        grasp_eq=grasp_eq,
        mj_model=gw.mj_model,
    )
    session = Session(session_id="grasp_smoke", ws=None, contract=contract)  # type: ignore[arg-type]
    session.joined = True
    session.room = room
    session.controlled_entity_id = mech.entity_id
    mech.controlled = True

    # Reach pose with tip near crate height (~0.4 m).
    for name, q in (("arm_yaw", 0.0), ("arm_shoulder", 1.4), ("arm_elbow", 0.0), ("gripper", 0.05)):
        mech._data.qpos[mech._pos_qadr[name]] = q
        mech.joint_targets[name] = q
    mujoco.mj_forward(mech._model, data)

    tip_id = mujoco.mj_name2id(mech._model, mujoco.mjtObj.mjOBJ_BODY, f"{mech.entity_id}/gripper_base")
    tip = data.xpos[tip_id]
    prop.reset_pose(
        {
            "x": float(tip[0]),
            "y": float(tip[1]),
            "z": float(tip[2]),
            "yaw": 0.0,
        }
    )

    # Close gripper → sticky weld via proximity.
    mech.joint_targets["gripper"] = 0.0
    for _ in range(40):
        mech.apply_ctrl()
        room.step_physics(0.02)
        gw._update_sticky_grasps(room)
        prop.pull_state()

    eq_id = grasp_eq.get((mech.entity_id, prop.entity_id))
    if eq_id is None or int(data.eq_active[eq_id]) != 1:
        print(
            f"FAIL: expected sticky weld engaged (eq={eq_id} active="
            f"{None if eq_id is None else int(data.eq_active[eq_id])})",
            file=sys.stderr,
        )
        return 1

    # Lift arm (raise tip well above spawn height).
    mech.joint_targets["arm_shoulder"] = -0.2
    mech.joint_targets["arm_elbow"] = -0.8
    for _ in range(150):
        mech.apply_ctrl()
        room.step_physics(0.02)
        gw._update_sticky_grasps(room)
        prop.pull_state()
        events = evaluate_objectives(session)
        if any(e.get("objective_id") == "obj_lift_crate" for e in events):
            print(f"grasp-lift OK z={prop.z:.3f}")
            return 0

    tip = data.xpos[tip_id]
    print(
        f"FAIL: no grasp_lift objective (prop z={prop.z:.3f} tip_z={float(tip[2]):.3f})",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
