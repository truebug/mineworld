"""F7 acceptance: two DiffBot chassis in one MjData must not cross when pushed together."""

from __future__ import annotations

import json
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[1]
sys.path = [p for p in sys.path if Path(p).resolve() != _REPO]

import mujoco

MODELS = _REPO / "mujoco" / "models"
CONTRACT = _REPO / "examples" / "contracts" / "tutorial_01.json"


def build_dual_world() -> mujoco.MjModel:
    """Mirror gateway F7 world construction (ground + 2 prefixed mechs)."""
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    spec = mujoco.MjSpec.from_file(str(MODELS / "world_flat.xml"))
    chassis = spec.worldbody.first_body()
    if chassis is not None and (chassis.name or "") == "chassis":
        spec.delete(chassis)
    for spawn in contract.get("mech_spawns") or []:
        eid = str(spawn["id"])
        rel = str(spawn.get("model_ref") or "mechs/diffbot_planar.xml")
        child = mujoco.MjSpec.from_file(str(MODELS / rel))
        frame = spec.worldbody.add_frame(name=f"frame_{eid}", pos=[0.0, 0.0, 0.0])
        spec.attach(child, prefix=f"{eid}/", frame=frame)
    return spec.compile()


def main() -> int:
    model = build_dual_world()
    data = mujoco.MjData(model)

    def qadr(name: str) -> int:
        jid = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, name)
        return int(model.jnt_qposadr[jid])

    ya = qadr("mech_player/slide_y")
    yb = qadr("mech_player_b/slide_y")
    data.qpos[ya] = 0.0
    data.qpos[yb] = 0.95  # ~1 m boxes nearly touching
    mujoco.mj_forward(model, data)

    act_a = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_ACTUATOR, "mech_player/vy")
    act_b = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_ACTUATOR, "mech_player_b/vy")
    max_ncon = 0
    for _ in range(150):
        data.ctrl[:] = 0.0
        data.ctrl[act_a] = 1.0
        data.ctrl[act_b] = -1.0
        mujoco.mj_step(model, data)
        max_ncon = max(max_ncon, int(data.ncon))

    ya_f, yb_f = float(data.qpos[ya]), float(data.qpos[yb])
    crossed = ya_f > yb_f
    print(f"final y A={ya_f:.3f} B={yb_f:.3f} max_ncon={max_ncon} crossed={crossed}")
    if crossed or max_ncon < 1:
        print("F7 FAIL: expected contact and no crossing")
        return 1
    print("F7 PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
