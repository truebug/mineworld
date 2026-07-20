"""IL flywheel: record grasp→place demo, export obj_place_block, bc_offline_check."""

from __future__ import annotations

import argparse
import shutil
import sys
import uuid
from pathlib import Path

import mujoco

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "gateway"))
sys.path.insert(0, str(REPO / "scripts"))

from echo_server import (  # noqa: E402
    EchoGateway,
    Room,
    Session,
    _prop_touches_gripper,
    evaluate_objectives,
    load_contract,
)
from recorder import SessionRecorder  # noqa: E402
from recording_store import export_trajectories  # noqa: E402
from bc_offline_check import check_csv  # noqa: E402


def _step_record(
    *,
    session: Session,
    room: Room,
    mech,
    prop,
    recorder: SessionRecorder,
    tick: int,
    events: list | None = None,
) -> int:
    """One sim tick + frame write. Returns next tick."""
    mech.apply_ctrl()
    room.step_physics(0.02)
    prop.pull_state()
    room.tick = tick
    entities = [m.to_entity_state() for m in room.mechs.values()] + [
        p.to_entity_state() for p in room.props.values()
    ]
    cmd = {
        "entity_id": mech.entity_id,
        "control_mode": "joint_targets",
        "joint_targets": dict(mech.joint_targets),
    }
    recorder.write_frame(
        tick=tick,
        cmd=cmd,
        state={"kind": "full", "entities": entities},
        events=events or [],
    )
    return tick + 1


def _hold(
    *,
    session: Session,
    room: Room,
    mech,
    prop,
    recorder: SessionRecorder,
    tick: int,
    n: int,
) -> int:
    """Record n ticks with current joint targets (denser IL sample)."""
    for _ in range(n):
        tick = _step_record(
            session=session, room=room, mech=mech, prop=prop, recorder=recorder, tick=tick
        )
    return tick


def run_recorded_place(record_dir: Path) -> tuple[int, Path | None]:
    """Run grasp→place with SessionRecorder; return (rc, session_dir)."""
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
        return 1, None
    mech = mechs["mech_player"]
    prop = props["prop_block"]
    room = Room(
        room_id="il_place",
        contract=contract,
        mechs=mechs,
        props=props,
        mj_data=data,
        grasp_eq=grasp_eq,
        mj_model=gw.mj_model,
    )
    sid = f"il-place-{uuid.uuid4().hex[:12]}"
    session = Session(session_id=sid, ws=None, contract=contract)  # type: ignore[arg-type]
    session.joined = True
    session.room = room
    session.controlled_entity_id = mech.entity_id
    session.space_id = "mw-il-place-demo"
    session.route_kind = "mineworld_level"
    mech.controlled = True

    record_dir.mkdir(parents=True, exist_ok=True)
    recorder = SessionRecorder(
        record_dir,
        session_id=sid,
        contract=contract,
        protocol_version="0.1",
        dt=0.02,
        sim_hz=50,
        state_hz=20,
        player_id="il_place_smoke",
        space_id=session.space_id,
        route_kind=session.route_kind,
    )
    session.recorder = recorder
    tick = 1

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
        tick = _step_record(
            session=session, room=room, mech=mech, prop=prop, recorder=recorder, tick=tick
        )
        if _prop_touches_gripper(mech._model, data, mech.entity_id, prop.entity_id):
            contacting = True
            break
    if not contacting:
        recorder.close("fail")
        print("FAIL: gripper never contacted prop", file=sys.stderr)
        return 1, recorder.dir

    mech.joint_targets["arm_shoulder"] = -0.2
    mech.joint_targets["arm_elbow"] = -0.8
    lifted = False
    for _ in range(200):
        tick = _step_record(
            session=session, room=room, mech=mech, prop=prop, recorder=recorder, tick=tick
        )
        events = evaluate_objectives(session)
        if any(e.get("objective_id") == "obj_lift_block" for e in events):
            lifted = True
            # Keep lifting briefly for denser joint rows (do not hold pre-lift — prop slips).
            tick = _hold(
                session=session,
                room=room,
                mech=mech,
                prop=prop,
                recorder=recorder,
                tick=tick,
                n=40,
            )
            break
    if not lifted:
        recorder.close("fail")
        print(f"FAIL: lift milestone missing (z={prop.z:.3f})", file=sys.stderr)
        return 1, recorder.dir

    prop.reset_pose({"x": 15.0, "y": -8.0, "z": 1.05, "yaw": 0.0})
    mech.joint_targets["gripper"] = 0.05
    mujoco.mj_forward(mech._model, data)
    placed = False
    for _ in range(40):
        tick = _step_record(
            session=session, room=room, mech=mech, prop=prop, recorder=recorder, tick=tick
        )
        events = evaluate_objectives(session)
        if any(e.get("objective_id") == "obj_place_block" for e in events):
            placed = True
            break
    if not placed:
        recorder.close("fail")
        print("FAIL: no place objective", file=sys.stderr)
        return 1, recorder.dir

    tick = _hold(
        session=session, room=room, mech=mech, prop=prop, recorder=recorder, tick=tick, n=20
    )
    recorder.set_task_id("obj_place_block")
    recorder.set_outcome("success")
    recorder.close("success")
    print(
        f"il-place recorded OK frames={recorder.num_frames} "
        f"dir={recorder.dir} space_id={session.space_id}"
    )
    return 0, recorder.dir


def main() -> int:
    """Record place demo → export CSV → bc_offline_check."""
    parser = argparse.ArgumentParser(description="IL grasp-place record + export + BC check")
    parser.add_argument(
        "--record-dir",
        type=Path,
        default=REPO / "recordings" / "il_place_sessions",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO / "recordings" / "exports" / "il_place.csv",
    )
    parser.add_argument("--min-rows", type=int, default=10)
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Keep record-dir (default: wipe then recreate)",
    )
    args = parser.parse_args()

    record_dir = args.record_dir.resolve()
    if record_dir.exists() and not args.keep:
        shutil.rmtree(record_dir)
    record_dir.mkdir(parents=True, exist_ok=True)

    rc, _sess = run_recorded_place(record_dir)
    if rc != 0:
        return rc

    out = args.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = export_trajectories(
        record_dir,
        out,
        format="csv",
        level_id="demo_workshop",
        task_id="obj_place_block",
        outcome="success",
    )
    if rows < 1:
        print(f"FAIL: export rows={rows}", file=sys.stderr)
        return 1
    print(f"exported {rows} row(s) -> {out}")

    check_rc = check_csv(out, min_rows=max(1, args.min_rows))
    if check_rc != 0:
        return check_rc
    print("il-place flywheel OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
