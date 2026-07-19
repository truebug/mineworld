"""T2.1 acceptance: headless stability of box_mech on flat ground.

Applies a constant velocity command [vx, vy, yaw_rate] at the POC control
rate (50 Hz; internal integrator steps at the model's 2 ms timestep) and
verifies, over --seconds of simulated time:

  1. state stays finite (no NaN / divergence)
  2. velocity servos track the command (post-settle error < tol)
  3. trajectory matches planar kinematics theory (circle of radius vx/w)
  4. chassis height stays put (planar model, no vertical drift)

Exit 0 on PASS, 1 on FAIL. Mirrors how the gateway will drive the model.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

# Repo folder `mujoco/` shadows the pip package; prefer site-packages.
_REPO = Path(__file__).resolve().parents[2]
sys.path = [p for p in sys.path if Path(p).resolve() != _REPO]

import mujoco
import numpy as np

DT_TICK = 0.02  # POC control rate (50 Hz)


def main() -> int:
    parser = argparse.ArgumentParser()
    default_model = Path(__file__).resolve().parents[1] / "models" / "world_flat.xml"
    parser.add_argument("--model", type=Path, default=default_model)
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--vx", type=float, default=1.0)
    parser.add_argument("--vy", type=float, default=0.0)
    parser.add_argument("--yaw-rate", type=float, default=0.5)
    parser.add_argument("--vel-tol", type=float, default=0.05)
    parser.add_argument("--pos-tol", type=float, default=0.3)
    args = parser.parse_args()

    model = mujoco.MjModel.from_xml_path(str(args.model))
    data = mujoco.MjData(model)
    substeps = int(round(DT_TICK / model.opt.timestep))
    ticks = int(round(args.seconds / DT_TICK))

    jnt = lambda n: mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, n)
    ax = model.jnt_qposadr[jnt("slide_x")]
    ay = model.jnt_qposadr[jnt("slide_y")]
    ayaw = model.jnt_qposadr[jnt("yaw_z")]
    dx = model.jnt_dofadr[jnt("slide_x")]
    dy = model.jnt_dofadr[jnt("slide_y")]
    dyaw = model.jnt_dofadr[jnt("yaw_z")]
    chassis = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, "chassis")
    mujoco.mj_forward(model, data)
    z0 = float(data.xpos[chassis][2])  # planar models keep constant height

    settle_ticks = int(0.5 / DT_TICK)  # ignore servo spin-up transient
    max_vel_err = 0.0
    distance = 0.0
    prev_xy = None

    for tick in range(ticks):
        # cmd is body-frame; slide joints translate in the parent (world)
        # frame (they compose before the hinge). Convert — this is exactly
        # the mapping the gateway applies in T2.2.
        yaw = float(data.qpos[ayaw])
        c, s = math.cos(yaw), math.sin(yaw)
        ctrl_world = np.array([
            c * args.vx - s * args.vy,
            s * args.vx + c * args.vy,
            args.yaw_rate,
        ])
        data.ctrl[:] = ctrl_world
        for _ in range(substeps):
            mujoco.mj_step(model, data)
        if not np.isfinite(data.qpos).all() or not np.isfinite(data.qvel).all():
            print(f"FAIL: non-finite state at t={data.time:.2f}s")
            return 1
        xy = (data.qpos[ax], data.qpos[ay])
        if prev_xy is not None:
            distance += math.hypot(xy[0] - prev_xy[0], xy[1] - prev_xy[1])
        prev_xy = xy
        if tick >= settle_ticks:
            err = max(
                abs(data.qvel[dx] - ctrl_world[0]),
                abs(data.qvel[dy] - ctrl_world[1]),
                abs(data.qvel[dyaw] - ctrl_world[2]),
            )
            max_vel_err = max(max_vel_err, err)

    t = args.seconds
    theta = args.yaw_rate * t
    # Planar kinematics, constant body-frame velocity (Z-up):
    #   x = (vx/w) sin(wt) + (vy/w)(cos(wt) - 1)
    #   y = (vx/w)(1 - cos(wt)) + (vy/w) sin(wt)
    if abs(args.yaw_rate) > 1e-9:
        exp_x = (args.vx / args.yaw_rate) * math.sin(theta) + (args.vy / args.yaw_rate) * (math.cos(theta) - 1.0)
        exp_y = (args.vx / args.yaw_rate) * (1.0 - math.cos(theta)) + (args.vy / args.yaw_rate) * math.sin(theta)
    else:
        exp_x, exp_y = args.vx * t, args.vy * t
    pos_err = math.hypot(data.qpos[ax] - exp_x, data.qpos[ay] - exp_y)
    yaw_err = abs(data.qpos[ayaw] - theta)
    z = float(data.xpos[chassis][2])

    print(f"model: {args.model.name}  sim_time: {data.time:.2f}s  ticks: {ticks}")
    print(f"cmd (body frame): vx={args.vx} vy={args.vy} yaw_rate={args.yaw_rate}")
    print(f"max_vel_err(post-settle): {max_vel_err:.4f}  (tol {args.vel_tol})")
    print(f"end pos: ({data.qpos[ax]:.3f}, {data.qpos[ay]:.3f})  "
          f"expected ({exp_x:.3f}, {exp_y:.3f})  err {pos_err:.3f} (tol {args.pos_tol})")
    print(f"yaw: {data.qpos[ayaw]:.3f}  expected {theta:.3f}  err {yaw_err:.3f}")
    print(f"distance traveled: {distance:.3f} m  chassis z: {z:.3f} (z0={z0:.3f})")

    ok = (
        max_vel_err < args.vel_tol
        and pos_err < args.pos_tol
        and yaw_err < 0.05
        and abs(z - z0) < 0.01
    )
    print("T2.1 PASS" if ok else "T2.1 FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
