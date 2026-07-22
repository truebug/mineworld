"""MineWorld POC WebSocket gateway.

Physics backends (--physics):
  fake   - in-process kinematic integrator (POC-A; regression fallback)
  mujoco - real MuJoCo sim (POC-B / T2.2): cmd -> ctrl, state <- qpos.
           Contract static_obstacles are appended as static geoms (T2.3).

Rooms (W2.3 / W3):
  join.payload.room_id omitted → private room (= session_id), one member;
  except demo_hub → room "hub", and demo_city → shared room "city" (max 5).
  room_id "demo" → shared workshop room, max 2 members; F7: one shared MjData so
  mechs can collide (joints/actuators prefixed by entity_id).

Recording (T2.5): on join, writes recordings/sessions/<id>/header.json + frames.jsonl.
Joints (T2.6 / F6): entity_state includes joints / joint_vels (planar + wheels).
F7: one shared MjData per Room so mechs can collide (prefixed joints/actuators).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import math
import sys
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import websockets
from websockets.asyncio.server import ServerConnection, serve

from recorder import SessionRecorder
from score_client import build_and_post

try:  # optional: only --physics mujoco needs it
    import mujoco
except ImportError:  # pragma: no cover
    mujoco = None

_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))
from mw_platform.scoring import compute_points  # noqa: E402

LOG = logging.getLogger("mineworld.gateway")

PROTOCOL_VERSION = "0.1"
DT = 0.02
SIM_HZ = 50
STATE_HZ = 20
STATE_EVERY_N_TICKS = max(1, SIM_HZ // STATE_HZ)
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONTRACT = REPO_ROOT / "examples" / "contracts" / "demo_workshop.json"
CONTRACTS_DIR = REPO_ROOT / "examples" / "contracts"
DEFAULT_RECORD_DIR = REPO_ROOT / "recordings" / "sessions"
OBSTACLE_FRICTION = (0.8, 0.02, 0.01)  # aligned with ground/chassis defaults
DEMO_ROOM_ID = "demo"
DEMO_ROOM_MAX = 2
CITY_ROOM_ID = "city"
CITY_ROOM_MAX = 5
RACE_ROOM_ID = "race"
RACE_ROOM_MAX = 6
HUB_ROOM_ID = "hub"
HUB_ROOM_MAX = 8


def _yaw_to_quat(yaw: float) -> dict[str, float]:
    """Z-up yaw (radians) → wxyz quaternion."""
    half = 0.5 * yaw
    return {"qw": math.cos(half), "qx": 0.0, "qy": 0.0, "qz": math.sin(half)}


class CmdRejected(Exception):
    """Client cmd rejected with a protocol error code."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class MechState:
    entity_id: str
    x: float = 0.0
    y: float = 0.0
    z: float = 0.5
    yaw: float = 0.0
    vx: float = 0.0
    vy: float = 0.0
    yaw_rate: float = 0.0
    controlled: bool = False
    joint_targets: dict[str, float] = field(default_factory=dict)

    def reset_pose(self, pose: dict[str, Any]) -> None:
        self.x = float(pose.get("x", 0.0))
        self.y = float(pose.get("y", 0.0))
        self.z = float(pose.get("z", 0.5))
        self.yaw = float(pose.get("yaw", 0.0))

    def _apply_joint_targets(self, targets: Any) -> None:
        """Validate and merge joint_targets; base class rejects all names."""
        if not isinstance(targets, dict):
            raise CmdRejected("BAD_JOINT_TARGETS", "joint_targets must be an object")
        unknown = [str(k) for k in targets]
        if unknown:
            raise CmdRejected(
                "UNKNOWN_JOINT",
                f"unknown joint_targets: {', '.join(unknown)}",
            )

    def apply_cmd(self, payload: dict[str, Any]) -> list[dict[str, Any]]:
        """Apply cmd payload; return events to emit."""
        events: list[dict[str, Any]] = []
        action = payload.get("action")
        if action == "take_control":
            self.controlled = True
            events.append(
                {
                    "event_type": "player_take_control",
                    "entity_id": self.entity_id,
                    "detail": {},
                }
            )
            return events
        if action == "release_control":
            self.controlled = False
            self.vx = self.vy = self.yaw_rate = 0.0
            events.append(
                {
                    "event_type": "player_release_control",
                    "entity_id": self.entity_id,
                    "detail": {},
                }
            )
            return events

        if not self.controlled:
            return events
        mode = payload.get("control_mode", "velocity")
        if mode == "velocity":
            self.vx = float(payload.get("vx", 0.0))
            self.vy = float(payload.get("vy", 0.0))
            self.yaw_rate = float(payload.get("yaw_rate", 0.0))
        if "joint_targets" in payload:
            self._apply_joint_targets(payload.get("joint_targets"))
        return events

    def step(self, dt: float) -> None:
        if not self.controlled:
            return
        # Body-frame velocity → world XY (Z-up).
        c, s = math.cos(self.yaw), math.sin(self.yaw)
        self.x += (c * self.vx - s * self.vy) * dt
        self.y += (s * self.vx + c * self.vy) * dt
        self.yaw += self.yaw_rate * dt

    def to_entity_state(self) -> dict[str, Any]:
        q = _yaw_to_quat(self.yaw)
        return {
            "entity_id": self.entity_id,
            "base_pose": {
                "x": self.x,
                "y": self.y,
                "z": self.z,
                "yaw": self.yaw,
                **q,
            },
            "velocities": {"vx": self.vx, "vy": self.vy, "vz": 0.0},
            "joints": {
                "slide_x": self.x,
                "slide_y": self.y,
                "yaw_z": self.yaw,
            },
            "joint_vels": {
                "slide_x": self.vx,
                "slide_y": self.vy,
                "yaw_z": self.yaw_rate,
            },
        }


class MujocoMech(MechState):
    """MuJoCo-backed mech. cmd writes ctrl, state reads MjData.

    The chassis slide joints translate in the parent (world) frame (they
    compose before the hinge), so the body-frame velocity command must be
    rotated by the current yaw — same math as the fake integrator.

    F7: Room shares one MjData; joint/actuator names are prefixed
    ``{entity_id}/``. ``apply_ctrl`` runs per mech; Room calls ``mj_step``
    once; then ``pull_state`` reads qpos and syncs F6 wheel kinematics.
    """

    def __init__(
        self,
        entity_id: str,
        model: "mujoco.MjModel",
        data: "mujoco.MjData",
        *,
        prefix: str = "",
    ) -> None:
        super().__init__(entity_id)
        self._model = model
        self._data = data
        self._prefix = prefix
        jnt = lambda n: mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, f"{prefix}{n}")
        act = lambda n: mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_ACTUATOR, f"{prefix}{n}")
        self._qx = model.jnt_qposadr[jnt("slide_x")]
        self._qy = model.jnt_qposadr[jnt("slide_y")]
        self._qyaw = model.jnt_qposadr[jnt("yaw_z")]
        self._dx = model.jnt_dofadr[jnt("slide_x")]
        self._dy = model.jnt_dofadr[jnt("slide_y")]
        self._dyaw = model.jnt_dofadr[jnt("yaw_z")]
        self._act_vx = act("vx")
        self._act_vy = act("vy")
        self._act_yaw = act("yaw_rate")
        self._chassis = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, f"{prefix}chassis")
        self._wheel_left: tuple[str, int, int] | None = None
        self._wheel_right: tuple[str, int, int] | None = None
        self._track = 0.0
        self._wheel_r = 0.15
        self._wheel_angle_l = 0.0
        self._wheel_angle_r = 0.0
        self._pos_acts: dict[str, int] = {}
        self._pos_qadr: dict[str, int] = {}
        self._pos_dadr: dict[str, int] = {}
        self._resolve_diff_drive()
        self._resolve_position_actuators()
        self._substeps = max(1, int(round(DT / model.opt.timestep)))
        self.reset_pose({})

    def _resolve_position_actuators(self) -> None:
        """Map non-chassis actuators (arm/gripper) for joint_targets (V1b)."""
        chassis = {"vx", "vy", "yaw_rate"}
        model = self._model
        for aid in range(model.nu):
            aname = mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_ACTUATOR, aid) or ""
            if self._prefix and not aname.startswith(self._prefix):
                continue
            short = aname[len(self._prefix) :] if self._prefix else aname
            if short in chassis:
                continue
            jid = int(model.actuator_trnid[aid, 0])
            if jid < 0:
                continue
            self._pos_acts[short] = aid
            self._pos_qadr[short] = int(model.jnt_qposadr[jid])
            self._pos_dadr[short] = int(model.jnt_dofadr[jid])
            self.joint_targets[short] = float(self._data.qpos[self._pos_qadr[short]])
        if self._pos_acts:
            LOG.info(
                "V1b position acts entity=%s joints=%s",
                self.entity_id,
                sorted(self._pos_acts),
            )

    def _apply_joint_targets(self, targets: Any) -> None:
        """Merge validated joint_targets into held position setpoints."""
        if not isinstance(targets, dict):
            raise CmdRejected("BAD_JOINT_TARGETS", "joint_targets must be an object")
        unknown = [str(k) for k in targets if str(k) not in self._pos_acts]
        if unknown:
            raise CmdRejected(
                "UNKNOWN_JOINT",
                f"unknown joint_targets: {', '.join(unknown)}",
            )
        for key, val in targets.items():
            self.joint_targets[str(key)] = float(val)

    def _resolve_diff_drive(self) -> None:
        """Pick left/right wheel hinge joints for this mech prefix."""
        model = self._model
        candidates: list[tuple[str, int, int, float]] = []
        for jid in range(model.njnt):
            jname = mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_JOINT, jid) or ""
            if self._prefix and not jname.startswith(self._prefix):
                continue
            short = jname[len(self._prefix) :] if self._prefix else jname
            if "wheel" not in short.lower():
                continue
            if short in ("slide_x", "slide_y", "yaw_z"):
                continue
            if model.jnt_type[jid] != mujoco.mjtJoint.mjJNT_HINGE:
                continue
            body_id = int(model.jnt_bodyid[jid])
            y = float(model.body_pos[body_id][1])
            gadr = int(model.body_geomadr[body_id])
            radius = float(model.geom_size[gadr][0]) if gadr >= 0 else 0.15
            candidates.append(
                (jname, int(model.jnt_qposadr[jid]), int(model.jnt_dofadr[jid]), y)
            )
            self._wheel_r = radius
        if len(candidates) < 2:
            return
        candidates.sort(key=lambda c: c[3])
        left, right = candidates[0], candidates[-1]
        self._wheel_left = (left[0], left[1], left[2])
        self._wheel_right = (right[0], right[1], right[2])
        self._track = abs(right[3] - left[3])
        logging.getLogger("mineworld.gateway").info(
            "F6 diff-drive entity=%s track=%.3f r=%.3f joints=%s/%s",
            self.entity_id,
            self._track,
            self._wheel_r,
            left[0],
            right[0],
        )

    def reset_pose(self, pose: dict[str, Any]) -> None:
        super().reset_pose(pose)
        if not hasattr(self, "_data"):
            return
        self._data.qpos[self._qx] = self.x
        self._data.qpos[self._qy] = self.y
        self._data.qpos[self._qyaw] = self.yaw
        # Clear this mech's dofs only (shared MjData).
        self._data.qvel[self._dx] = 0.0
        self._data.qvel[self._dy] = 0.0
        self._data.qvel[self._dyaw] = 0.0
        self._data.ctrl[self._act_vx] = 0.0
        self._data.ctrl[self._act_vy] = 0.0
        self._data.ctrl[self._act_yaw] = 0.0
        self._wheel_angle_l = 0.0
        self._wheel_angle_r = 0.0
        if self._wheel_left is not None and self._wheel_right is not None:
            self._data.qpos[self._wheel_left[1]] = 0.0
            self._data.qpos[self._wheel_right[1]] = 0.0
            self._data.qvel[self._wheel_left[2]] = 0.0
            self._data.qvel[self._wheel_right[2]] = 0.0
        mujoco.mj_forward(self._model, self._data)

    def apply_ctrl(self) -> None:
        """Write chassis velocity + held arm/gripper position actuators."""
        if not self.controlled:
            self._data.ctrl[self._act_vx] = 0.0
            self._data.ctrl[self._act_vy] = 0.0
            self._data.ctrl[self._act_yaw] = 0.0
        else:
            yaw = float(self._data.qpos[self._qyaw])
            c, s = math.cos(yaw), math.sin(yaw)
            self._data.ctrl[self._act_vx] = c * self.vx - s * self.vy
            self._data.ctrl[self._act_vy] = s * self.vx + c * self.vy
            self._data.ctrl[self._act_yaw] = self.yaw_rate
        for name, aid in self._pos_acts.items():
            q = self.joint_targets.get(name)
            if q is None:
                q = float(self._data.qpos[self._pos_qadr[name]])
            self._data.ctrl[aid] = q

    def _sync_wheels(self, dt: float) -> None:
        """Overwrite wheel qpos/qvel from body vx / yaw_rate (kinematic DiffBot)."""
        if self._wheel_left is None or self._wheel_right is None or self._wheel_r <= 1e-6:
            return
        if not self.controlled:
            w_l = w_r = 0.0
        else:
            half_l = 0.5 * self._track
            w_l = (self.vx - self.yaw_rate * half_l) / self._wheel_r
            w_r = (self.vx + self.yaw_rate * half_l) / self._wheel_r
        self._wheel_angle_l += w_l * dt
        self._wheel_angle_r += w_r * dt
        self._data.qpos[self._wheel_left[1]] = self._wheel_angle_l
        self._data.qpos[self._wheel_right[1]] = self._wheel_angle_r
        self._data.qvel[self._wheel_left[2]] = w_l
        self._data.qvel[self._wheel_right[2]] = w_r

    def pull_state(self, dt: float) -> None:
        """Read chassis pose from shared MjData after Room mj_step."""
        self._sync_wheels(dt)
        d = self._data
        self.x = float(d.qpos[self._qx])
        self.y = float(d.qpos[self._qy])
        mujoco.mj_forward(self._model, d)
        self.z = float(d.xpos[self._chassis][2])
        self.yaw = float(d.qpos[self._qyaw])

    def step(self, dt: float) -> None:
        """Solo step (unused when Room owns shared mj_step); kept for tests."""
        self.apply_ctrl()
        for _ in range(self._substeps):
            mujoco.mj_step(self._model, self._data)
        self.pull_state(dt)

    def to_entity_state(self) -> dict[str, Any]:
        q = _yaw_to_quat(self.yaw)
        d = self._data
        joints = {
            "slide_x": float(d.qpos[self._qx]),
            "slide_y": float(d.qpos[self._qy]),
            "yaw_z": float(d.qpos[self._qyaw]),
        }
        joint_vels = {
            "slide_x": float(d.qvel[self._dx]),
            "slide_y": float(d.qvel[self._dy]),
            "yaw_z": float(d.qvel[self._dyaw]),
        }
        if self._wheel_left is not None and self._wheel_right is not None:
            for meta in (self._wheel_left, self._wheel_right):
                jname, qadr, dadr = meta
                short = jname[len(self._prefix) :] if self._prefix else jname
                joints[short] = float(d.qpos[qadr])
                joint_vels[short] = float(d.qvel[dadr])
        for name, qadr in self._pos_qadr.items():
            joints[name] = float(d.qpos[qadr])
            joint_vels[name] = float(d.qvel[self._pos_dadr[name]])
        return {
            "entity_id": self.entity_id,
            "base_pose": {"x": self.x, "y": self.y, "z": self.z, "yaw": self.yaw, **q},
            "velocities": {
                "vx": float(d.qvel[self._dx]),
                "vy": float(d.qvel[self._dy]),
                "vz": 0.0,
            },
            "joints": joints,
            "joint_vels": joint_vels,
        }


class DynamicProp:
    """Freejoint pushable/liftable box (T4.6 push + V3c grasp lift)."""

    def __init__(
        self,
        entity_id: str,
        model: "mujoco.MjModel",
        data: "mujoco.MjData",
        *,
        body_name: str,
        joint_prefix: str,
    ) -> None:
        self.entity_id = entity_id
        self._model = model
        self._data = data
        self._body = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, body_name)
        if self._body < 0:
            raise SystemExit(f"dynamic prop body missing: {body_name}")
        jname = f"{joint_prefix}free"
        jid = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, jname)
        if jid < 0:
            raise SystemExit(f"dynamic prop freejoint missing: {jname}")
        self._qadr = int(model.jnt_qposadr[jid])
        self._dadr = int(model.jnt_dofadr[jid])
        self.x = self.y = self.z = self.yaw = 0.0
        self.pull_state()

    def reset_pose(self, pose: dict[str, Any]) -> None:
        """Write spawn XYZ/yaw into freejoint qpos (quat wxyz)."""
        self._data.qpos[self._qadr + 0] = float(pose.get("x", 0.0))
        self._data.qpos[self._qadr + 1] = float(pose.get("y", 0.0))
        self._data.qpos[self._qadr + 2] = float(pose.get("z", 0.25))
        yaw = float(pose.get("yaw", 0.0))
        q = _yaw_to_quat(yaw)
        self._data.qpos[self._qadr + 3] = q["qw"]
        self._data.qpos[self._qadr + 4] = q["qx"]
        self._data.qpos[self._qadr + 5] = q["qy"]
        self._data.qpos[self._qadr + 6] = q["qz"]
        for i in range(6):
            self._data.qvel[self._dadr + i] = 0.0
        mujoco.mj_forward(self._model, self._data)
        self.pull_state()

    def pull_state(self) -> None:
        """Read body pose into fields for state broadcast."""
        pos = self._data.xpos[self._body]
        self.x = float(pos[0])
        self.y = float(pos[1])
        self.z = float(pos[2])
        # yaw from freejoint quat (wxyz)
        qw, qx, qy, qz = (float(self._data.qpos[self._qadr + i]) for i in range(3, 7))
        self.yaw = math.atan2(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz))

    def to_entity_state(self) -> dict[str, Any]:
        """Serialize prop as entity_state (no joints required)."""
        q = _yaw_to_quat(self.yaw)
        return {
            "entity_id": self.entity_id,
            "kind": "dynamic_prop",
            "base_pose": {"x": self.x, "y": self.y, "z": self.z, "yaw": self.yaw, **q},
        }


@dataclass
class Room:
    """Logical shared world: mechs + props + members; one tick for all members."""

    room_id: str
    contract: dict[str, Any]
    mechs: dict[str, MechState] = field(default_factory=dict)
    props: dict[str, DynamicProp] = field(default_factory=dict)
    members: dict[str, Session] = field(default_factory=dict)
    tick: int = 0
    max_members: int = 1
    # F7: shared MuJoCo state so mechs collide; None for fake physics.
    mj_data: Any = None
    mj_substeps: int = 1
    ## V3c: (mech_id, prop_id) → equality id for sticky grasp weld.
    grasp_eq: dict[tuple[str, str], int] = field(default_factory=dict)
    ## H1: compiled MjModel for this room's contract (may differ per level).
    mj_model: Any = None

    def free_spawn_id(self) -> str | None:
        """Return first mech spawn id not claimed by a joined member."""
        taken = {
            s.controlled_entity_id
            for s in self.members.values()
            if s.controlled_entity_id and s.joined and not s.closed
        }
        for spawn in self.contract.get("mech_spawns") or []:
            eid = spawn.get("id")
            if eid and eid not in taken and eid in self.mechs:
                return str(eid)
        return None

    def step_physics(self, dt: float) -> None:
        """Advance all mechs; MuJoCo rooms share one mj_step (F7)."""
        mujoco_mechs = [m for m in self.mechs.values() if isinstance(m, MujocoMech)]
        if self.mj_data is not None and mujoco_mechs:
            for mech in mujoco_mechs:
                mech.apply_ctrl()
            for _ in range(self.mj_substeps):
                mujoco.mj_step(mujoco_mechs[0]._model, self.mj_data)
            for mech in mujoco_mechs:
                mech.pull_state(dt)
            for prop in self.props.values():
                prop.pull_state()
            return
        for mech in self.mechs.values():
            mech.step(dt)
        self._clamp_hub_bounds()
        self._separate_hub_avatars()

    def _clamp_hub_bounds(self) -> None:
        """Keep hub avatars on walkable apron AABBs (FakeMech air walls)."""
        if not is_hub_contract(self.contract):
            return
        mw = contract_mw(self.contract)
        bounds = mw.get("bounds") if isinstance(mw.get("bounds"), dict) else {}
        try:
            half_x = float(bounds.get("half_x", 18.5))
            half_y = float(bounds.get("half_y", 14.5))
        except (TypeError, ValueError):
            half_x, half_y = 18.5, 14.5
        walkable = _hub_walkable_aabbs(bounds, half_x, half_y)
        for mech in self.mechs.values():
            # Outer envelope first.
            if mech.x < -half_x:
                mech.x = -half_x
                mech.vx = 0.0
            elif mech.x > half_x:
                mech.x = half_x
                mech.vx = 0.0
            if mech.y < -half_y:
                mech.y = -half_y
                mech.vy = 0.0
            elif mech.y > half_y:
                mech.y = half_y
                mech.vy = 0.0
            if not walkable:
                continue
            if any(_point_in_aabb(mech.x, mech.y, box) for box in walkable):
                pass
            else:
                nx, ny = _nearest_aabb_point(mech.x, mech.y, walkable)
                if abs(nx - mech.x) > 1e-6:
                    mech.vx = 0.0
                if abs(ny - mech.y) > 1e-6:
                    mech.vy = 0.0
                mech.x, mech.y = nx, ny
            blocked = _hub_blocked_aabbs(bounds)
            for box in blocked:
                if not _point_in_aabb(mech.x, mech.y, box):
                    continue
                # Push to nearest face of the blocked AABB.
                left = abs(mech.x - box["min_x"])
                right = abs(box["max_x"] - mech.x)
                bottom = abs(mech.y - box["min_y"])
                top = abs(box["max_y"] - mech.y)
                m = min(left, right, bottom, top)
                if m == left:
                    mech.x = box["min_x"] - 0.01
                elif m == right:
                    mech.x = box["max_x"] + 0.01
                elif m == bottom:
                    mech.y = box["min_y"] - 0.01
                else:
                    mech.y = box["max_y"] + 0.01
                mech.vx = mech.vy = 0.0

    def _separate_hub_avatars(self) -> None:
        """Soft circle push between occupied Hub avatars (FakeMech only)."""
        if not is_hub_contract(self.contract):
            return
        occupied_ids = {
            s.controlled_entity_id
            for s in self.members.values()
            if s.joined and not s.closed and s.controlled_entity_id
        }
        bodies = [m for eid, m in self.mechs.items() if eid in occupied_ids]
        if len(bodies) < 2:
            return
        min_dist = 1.1
        for i, a in enumerate(bodies):
            for b in bodies[i + 1 :]:
                dx = b.x - a.x
                dy = b.y - a.y
                dist = math.hypot(dx, dy)
                if dist < 1e-4:
                    b.x += min_dist * 0.5
                    continue
                if dist >= min_dist:
                    continue
                push = (min_dist - dist) * 0.5
                nx = dx / dist
                ny = dy / dist
                a.x -= nx * push
                a.y -= ny * push
                b.x += nx * push
                b.y += ny * push
                # Kill closing relative speed along contact normal.
                a.vx = a.vy = 0.0
                b.vx = b.vy = 0.0
        # Re-clamp after push so pairs cannot shove each other through walls.
        self._clamp_hub_bounds()


@dataclass
class Session:
    session_id: str
    ws: ServerConnection
    contract: dict[str, Any]
    joined: bool = False
    level_id: str | None = None
    room: Room | None = None
    controlled_entity_id: str | None = None
    pending_events: list[dict[str, Any]] = field(default_factory=list)
    closed: bool = False
    recorder: SessionRecorder | None = None
    completed_objectives: set[str] = field(default_factory=set)
    outcome: str | None = None
    ## Hub / join display (no account); see docs/18-hub-dungeon.md.
    player_name: str = "guest"
    profile: dict[str, Any] = field(default_factory=dict)
    ## E3: optional PMS/Space attribution (empty = native MineWorld level).
    space_id: str | None = None
    route_kind: str = "mineworld_level"
    ## E9 Hub: state broadcast divisor vs STATE_EVERY (1=full, 4=low, 0=paused).
    presence_state_divisor: int = 1

    @property
    def mech(self) -> MechState | None:
        """Assigned mech in the current room, if any."""
        if self.room is None or not self.controlled_entity_id:
            return None
        return self.room.mechs.get(self.controlled_entity_id)


def load_contract(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def contract_mw(contract: dict[str, Any]) -> dict[str, Any]:
    """Return extensions.mw bag (empty dict if missing)."""
    ext = contract.get("extensions")
    if not isinstance(ext, dict):
        return {}
    mw = ext.get("mw")
    return mw if isinstance(mw, dict) else {}


def contract_mw_il(contract: dict[str, Any]) -> dict[str, Any]:
    """Return extensions['mw.il'] bag (empty dict if missing)."""
    ext = contract.get("extensions")
    if not isinstance(ext, dict):
        return {}
    il = ext.get("mw.il")
    return il if isinstance(il, dict) else {}


def _il_primary_task_id(contract: dict[str, Any]) -> str | None:
    """Primary IL task_id from extensions.mw.il (terminal success objective)."""
    tid = contract_mw_il(contract).get("task_id")
    if tid is None:
        return None
    s = str(tid).strip()
    return s or None


def _il_time_limit_s(contract: dict[str, Any]) -> float | None:
    """Optional sim-time limit (seconds) from extensions.mw.il.time_limit_s."""
    raw = contract_mw_il(contract).get("time_limit_s")
    if raw is None:
        return None
    try:
        limit = float(raw)
    except (TypeError, ValueError):
        return None
    return limit if limit > 0 else None


def _hub_walkable_aabbs(
    bounds: dict[str, Any], half_x: float, half_y: float
) -> list[dict[str, float]]:
    """Parse walkable AABBs; clip to outer half extents. Empty → envelope-only."""
    raw = bounds.get("walkable")
    if not isinstance(raw, list):
        return []
    out: list[dict[str, float]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            min_x = max(-half_x, float(item["min_x"]))
            max_x = min(half_x, float(item["max_x"]))
            min_y = max(-half_y, float(item["min_y"]))
            max_y = min(half_y, float(item["max_y"]))
        except (KeyError, TypeError, ValueError):
            continue
        if min_x >= max_x or min_y >= max_y:
            continue
        out.append({"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y})
    return out


def _hub_blocked_aabbs(bounds: dict[str, Any]) -> list[dict[str, float]]:
    """Parse solid pillar / prop AABBs (FakeMech cannot enter)."""
    raw = bounds.get("blocked")
    if not isinstance(raw, list):
        return []
    out: list[dict[str, float]] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        try:
            min_x = float(item["min_x"])
            max_x = float(item["max_x"])
            min_y = float(item["min_y"])
            max_y = float(item["max_y"])
        except (KeyError, TypeError, ValueError):
            continue
        if min_x >= max_x or min_y >= max_y:
            continue
        out.append({"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y})
    return out


def _point_in_aabb(x: float, y: float, box: dict[str, float]) -> bool:
    """True if (x,y) is inside axis-aligned box."""
    return box["min_x"] <= x <= box["max_x"] and box["min_y"] <= y <= box["max_y"]


def _nearest_aabb_point(
    x: float, y: float, boxes: list[dict[str, float]]
) -> tuple[float, float]:
    """Project (x,y) onto the nearest walkable AABB edge/interior."""
    best_d = float("inf")
    best = (x, y)
    for box in boxes:
        cx = min(max(x, box["min_x"]), box["max_x"])
        cy = min(max(y, box["min_y"]), box["max_y"])
        d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
        if d < best_d:
            best_d = d
            best = (cx, cy)
    return best


def is_hub_contract(contract: dict[str, Any]) -> bool:
    """True for dungeon-gate hub: no MuJoCo, presence-only rooms."""
    if contract_mw(contract).get("mode") == "hub":
        return True
    return str(contract.get("level_id") or "") == "demo_hub"


def hub_max_members(contract: dict[str, Any]) -> int:
    """Max concurrent avatars in a hub room."""
    raw = contract_mw(contract).get("max_members", HUB_ROOM_MAX)
    try:
        return max(1, int(raw))
    except (TypeError, ValueError):
        return HUB_ROOM_MAX


def catalog_contracts(contracts_dir: Path = CONTRACTS_DIR) -> dict[str, Path]:
    """Map level_id → contract JSON path under examples/contracts (H1 lobby)."""
    out: dict[str, Path] = {}
    if not contracts_dir.is_dir():
        return out
    for path in sorted(contracts_dir.glob("*.json")):
        try:
            data = load_contract(path)
        except (OSError, json.JSONDecodeError):
            LOG.warning("skip unreadable contract %s", path)
            continue
        level_id = str(data.get("level_id") or path.stem)
        if level_id in out:
            LOG.warning("duplicate level_id %s: %s vs %s", level_id, out[level_id], path)
            continue
        out[level_id] = path
    return out


def point_in_aabb(x: float, y: float, z: float, mn: list[float], mx: list[float]) -> bool:
    """Return True if point lies inside an axis-aligned box (inclusive)."""
    return (
        float(mn[0]) <= x <= float(mx[0])
        and float(mn[1]) <= y <= float(mx[1])
        and float(mn[2]) <= z <= float(mx[2])
    )


def _gripper_q(mech: MechState) -> float | None:
    """Return current gripper slide qpos, or None if unavailable."""
    if not isinstance(mech, MujocoMech):
        return None
    qadr = mech._pos_qadr.get("gripper")
    if qadr is None:
        return None
    return float(mech._data.qpos[qadr])


def _gripper_command_closed(mech: MechState, closed_max: float) -> bool:
    """Return True if gripper is commanded closed and/or measured closed."""
    if not isinstance(mech, MujocoMech):
        return False
    target = mech.joint_targets.get("gripper")
    if target is not None and float(target) <= closed_max:
        return True
    gq = _gripper_q(mech)
    return gq is not None and gq <= closed_max


def _gripper_command_open(mech: MechState, open_min: float) -> bool:
    """Return True if gripper is commanded open and/or measured open (place)."""
    if not isinstance(mech, MujocoMech):
        return False
    target = mech.joint_targets.get("gripper")
    if target is not None and float(target) >= open_min:
        return True
    gq = _gripper_q(mech)
    return gq is not None and gq >= open_min


def _prop_touches_gripper(model: Any, data: Any, mech_id: str, prop_id: str) -> bool:
    """Return True if prop contacts any gripper/finger body of mech."""
    prefix = f"{mech_id}/"

    def is_grip(name: str) -> bool:
        return name.startswith(prefix) and ("finger" in name or "gripper" in name)

    for i in range(int(data.ncon)):
        con = data.contact[i]
        names: list[str] = []
        for gid in (int(con.geom1), int(con.geom2)):
            bid = int(model.geom_bodyid[gid])
            names.append(mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_BODY, bid) or "")
        a, b = names[0], names[1]
        if (a == prop_id and is_grip(b)) or (b == prop_id and is_grip(a)):
            return True
    return False


def _gripper_prop_close(model: Any, data: Any, mech_id: str, prop_id: str, max_dist: float) -> bool:
    """Return True if gripper_base is within max_dist of prop body."""
    g_id = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, f"{mech_id}/gripper_base")
    p_id = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, prop_id)
    if g_id < 0 or p_id < 0:
        return False
    delta = data.xpos[g_id] - data.xpos[p_id]
    return float((delta * delta).sum()) <= max_dist * max_dist


def _grasp_lift_ready(session: Session, obj: dict[str, Any]) -> tuple[bool, str | None]:
    """P1a: gripper closed + real contact + prop height above threshold (no weld)."""
    if session.room is None or session.room.mj_data is None:
        return False, None
    mech = session.mech
    if mech is None or not isinstance(mech, MujocoMech):
        return False, None
    params = obj.get("params") if isinstance(obj.get("params"), dict) else {}
    prop_id = str(params.get("entity_id") or params.get("subject") or "")
    if not prop_id:
        return False, None
    prop = session.room.props.get(prop_id)
    if prop is None:
        return False, None
    closed_max = float(params.get("gripper_closed_max", 0.02))
    min_z = float(params.get("min_z", 0.45))
    if not _gripper_command_closed(mech, closed_max):
        return False, None
    model = mech._model
    data = session.room.mj_data
    if not _prop_touches_gripper(model, data, mech.entity_id, prop_id):
        return False, None
    if prop.z < min_z:
        return False, None
    return True, prop.entity_id


def evaluate_objectives(session: Session) -> list[dict[str, Any]]:
    """Gateway-authoritative objective checks (T3.1 / V3a / V3c). Emit each once.

    ``reach_region`` defaults to the session mech. Set ``params.entity_id`` (or
    ``params.subject``) to a ``dynamic_prop`` id to require that prop enter the
    trigger AABB instead (workshop stow-crate).

    ``grasp_lift`` requires closed gripper + contact friction + prop ``min_z`` (P1a).
    Milestone only — does not set session ``outcome`` (terminal place/stow does).

    ``reach_region`` may set ``params.gripper_open_min`` so the subject must be
    released (place on bench/bin), not held closed over the AABB.

    When ``extensions.mw.il.task_id`` is set, only that objective sets
    ``outcome=success``; other ``reach_region`` hits are milestones (A1).
    """
    events: list[dict[str, Any]] = []
    if session.room is None or session.outcome:
        return events
    primary = _il_primary_task_id(session.contract)
    triggers = {t["id"]: t for t in (session.contract.get("triggers") or []) if t.get("id")}
    for obj in session.contract.get("objectives") or []:
        obj_id = obj.get("id")
        if not obj_id or obj_id in session.completed_objectives:
            continue
        obj_type = obj.get("type")
        if obj_type == "grasp_lift":
            ok, subject_id = _grasp_lift_ready(session, obj)
            if not ok or subject_id is None:
                continue
            session.completed_objectives.add(obj_id)
            events.append(
                {
                    "event_type": "objective_complete",
                    "objective_id": obj_id,
                    "entity_id": subject_id,
                    "detail": {"kind": "grasp_lift", "subject_id": subject_id},
                }
            )
            LOG.info(
                "session=%s objective_complete id=%s grasp_lift subject=%s",
                session.session_id,
                obj_id,
                subject_id,
            )
            continue
        if obj_type != "reach_region":
            continue
        trig = triggers.get(obj.get("target"))
        if not trig or trig.get("type") != "aabb":
            continue
        mn = trig.get("min") or []
        mx = trig.get("max") or []
        if len(mn) < 3 or len(mx) < 3:
            continue

        params = obj.get("params") if isinstance(obj.get("params"), dict) else {}
        subject_id = params.get("entity_id") or params.get("subject")
        if subject_id:
            prop = session.room.props.get(str(subject_id))
            if prop is None:
                continue
            px, py, pz = prop.x, prop.y, prop.z
            entity_id = prop.entity_id
        else:
            mech = session.mech
            if mech is None:
                continue
            px, py, pz = mech.x, mech.y, mech.z
            entity_id = mech.entity_id

        if not point_in_aabb(px, py, pz, mn, mx):
            continue
        requires = params.get("requires") or []
        if isinstance(requires, list) and requires:
            missing = [
                str(r)
                for r in requires
                if str(r) not in session.completed_objectives
            ]
            if missing:
                continue
        open_min = params.get("gripper_open_min")
        if open_min is not None:
            mech = session.mech
            if mech is None or not _gripper_command_open(mech, float(open_min)):
                continue
        session.completed_objectives.add(obj_id)
        terminal = params.get("terminal")
        if terminal is None:
            terminal = primary is None or str(obj_id) == primary
        else:
            terminal = bool(terminal)
        detail: dict[str, Any] = {
            "trigger_id": trig["id"],
            "subject_id": entity_id,
        }
        if terminal:
            session.outcome = "success"
        else:
            detail["kind"] = "milestone"
        events.append(
            {
                "event_type": "objective_complete",
                "objective_id": obj_id,
                "entity_id": entity_id,
                "detail": detail,
            }
        )
        LOG.info(
            "session=%s objective_complete id=%s subject=%s terminal=%s at (%.2f, %.2f, %.2f)",
            session.session_id,
            obj_id,
            entity_id,
            terminal,
            px,
            py,
            pz,
        )
    return events


def evaluate_time_limit(session: Session) -> list[dict[str, Any]]:
    """A1: emit objective_failed + outcome=fail when sim time exceeds mw.il.time_limit_s."""
    if session.room is None or session.outcome:
        return []
    limit = _il_time_limit_s(session.contract)
    if limit is None:
        return []
    t_sim = float(session.room.tick) * DT
    if t_sim < limit:
        return []
    oid = _il_primary_task_id(session.contract) or "time_limit"
    session.outcome = "fail"
    LOG.info(
        "session=%s objective_failed id=%s time_limit=%.1fs t_sim=%.1fs",
        session.session_id,
        oid,
        limit,
        t_sim,
    )
    return [
        {
            "event_type": "objective_failed",
            "objective_id": oid,
            "detail": {
                "kind": "time_limit",
                "limit_s": limit,
                "t_sim": round(t_sim, 3),
                "level_id": str(
                    session.level_id or session.contract.get("level_id") or ""
                ),
            },
        }
    ]


def envelope(
    msg_type: str,
    *,
    session_id: str | None = None,
    tick: int | None = None,
    payload: dict[str, Any] | None = None,
    **extra: Any,
) -> dict[str, Any]:
    msg: dict[str, Any] = {"type": msg_type}
    if session_id is not None:
        msg["session_id"] = session_id
    if tick is not None:
        msg["tick"] = tick
        msg["t_sim"] = round(tick * DT, 6)
    if payload is not None:
        msg["payload"] = payload
    msg.update(extra)
    return msg


async def send_json(ws: ServerConnection, msg: dict[str, Any]) -> None:
    await ws.send(json.dumps(msg, ensure_ascii=False, separators=(",", ":")))


class EchoGateway:
    """Single-process POC gateway: Room tick + WS fan-out."""

    def __init__(
        self,
        contract: dict[str, Any],
        physics: str = "fake",
        model_path: Path | None = None,
        record_dir: Path | None = DEFAULT_RECORD_DIR,
        record_every_n_ticks: int = 1,
        contract_path: Path | None = None,
    ) -> None:
        self.contract = contract
        self.contract_path = contract_path
        self._contract_mtime: float | None = None
        if contract_path is not None:
            try:
                self._contract_mtime = contract_path.stat().st_mtime
            except OSError:
                self._contract_mtime = None
        self.sessions: dict[str, Session] = {}
        self.rooms: dict[str, Room] = {}
        self.physics = physics
        self.record_dir = record_dir
        self.record_every_n_ticks = record_every_n_ticks
        self.model_path = model_path
        self.level_contracts = catalog_contracts()
        self._mj_models: dict[str, Any] = {}
        self.mj_model = None
        ## PL2: in-memory level disable set (join rejected until enable / restart).
        self.disabled_levels: set[str] = set()
        if physics == "mujoco":
            if mujoco is None:
                raise SystemExit("mujoco not installed: pip install mujoco==3.6.0")
            if model_path is None:
                raise SystemExit("--physics mujoco requires --model")
            default_level = str(contract.get("level_id") or "demo_workshop")
            self.mj_model = self._ensure_mj_model(contract)
            LOG.info(
                "mujoco levels registered=%s default=%s",
                sorted(self.level_contracts),
                default_level,
            )

    def rooms_snapshot(self) -> list[dict[str, Any]]:
        """PL2: read-only live room list (no poses)."""
        out: list[dict[str, Any]] = []
        for room in self.rooms.values():
            members = []
            for sess in room.members.values():
                if not sess.joined or sess.closed:
                    continue
                members.append(
                    {
                        "session_id": sess.session_id,
                        "player_name": sess.player_name,
                        "entity_id": sess.controlled_entity_id,
                        "space_id": sess.space_id,
                    }
                )
            level_id = str(room.contract.get("level_id") or "")
            out.append(
                {
                    "room_id": room.room_id,
                    "level_id": level_id,
                    "seed": room.contract.get("seed"),
                    "member_count": len(members),
                    "max_members": room.max_members,
                    "tick": room.tick,
                    "hub": is_hub_contract(room.contract),
                    "shared_mj": room.mj_data is not None,
                    "members": members,
                }
            )
        out.sort(key=lambda r: str(r.get("room_id") or ""))
        return out

    def contracts_snapshot(self) -> dict[str, Any]:
        """PL2: catalog levels + disabled set."""
        levels = []
        for lid in sorted(self.level_contracts):
            path = self.level_contracts[lid]
            levels.append(
                {
                    "level_id": lid,
                    "path": str(path),
                    "disabled": lid in self.disabled_levels,
                }
            )
        return {
            "levels": levels,
            "disabled_levels": sorted(self.disabled_levels),
            "default_level_id": str(self.contract.get("level_id") or ""),
        }

    def admin_status(self) -> dict[str, Any]:
        """PL2: compact gateway status."""
        return {
            "physics": self.physics,
            "room_count": len(self.rooms),
            "session_count": len([s for s in self.sessions.values() if not s.closed]),
            "recording": self.record_dir is not None,
            "disabled_levels": sorted(self.disabled_levels),
        }

    def disable_level(self, level_id: str) -> None:
        """Reject new joins for level_id until enable_level."""
        lid = level_id.strip()
        if lid:
            self.disabled_levels.add(lid)
            LOG.info("PL2 disable level_id=%s", lid)

    def enable_level(self, level_id: str) -> None:
        """Re-allow joins for level_id."""
        lid = level_id.strip()
        self.disabled_levels.discard(lid)
        LOG.info("PL2 enable level_id=%s", lid)

    def _maybe_reload_contract(self) -> None:
        """Hot-reload contract (+ rebuild MuJoCo world) when the file changes (D9).

        Active rooms keep their old MjData/contract until empty; new rooms use
        the reloaded world.
        """
        if self.contract_path is None:
            return
        try:
            mtime = self.contract_path.stat().st_mtime
        except OSError:
            return
        if self._contract_mtime is not None and mtime == self._contract_mtime:
            return
        prev_seed = self.contract.get("seed")
        self.contract = load_contract(self.contract_path)
        self._contract_mtime = mtime
        if self.physics == "mujoco" and self.model_path is not None:
            level = str(self.contract.get("level_id") or "")
            self._mj_models.pop(level, None)
            self.mj_model = self._ensure_mj_model(self.contract)
        # Drop empty rooms so the next join recreates with the new contract.
        dead = [
            rid
            for rid, room in self.rooms.items()
            if not any(s.joined and not s.closed for s in room.members.values())
        ]
        for rid in dead:
            del self.rooms[rid]
        LOG.info(
            "contract reloaded seed %s → %s (dropped %d empty rooms)",
            prev_seed,
            self.contract.get("seed"),
            len(dead),
        )

    def _feature_flags(self) -> list[str]:
        """Return hello/recording feature tags for the active physics backend."""
        return ["fake_kinematics" if self.physics == "fake" else "mujoco"]

    def _close_recorder(self, session: Session, outcome: str) -> None:
        """Finalize session recording if one is open; report score on success."""
        duration = 0.0
        if session.recorder is not None:
            duration = float(session.recorder.duration_sim_s)
            try:
                session.recorder.close(outcome=outcome)
            except Exception:
                LOG.exception("recorder close failed session=%s", session.session_id)
            session.recorder = None
        elif session.room is not None:
            duration = float(session.room.tick) * DT
        if outcome == "success":
            self._report_score(session, duration)
        elif outcome == "fail":
            # Idempotent: may already have posted from sim_loop on time_limit.
            self._report_score(session, duration)

    def _report_score(self, session: Session, duration_sim_s: float) -> None:
        """SC2: post points to platform API (idempotent by session_id)."""
        pid = str((session.profile or {}).get("id") or "").strip()
        level_id = str(session.level_id or session.contract.get("level_id") or "")
        task_id = session.contract.get("task_id")
        if not task_id:
            task_id = _il_primary_task_id(session.contract)
        if not task_id:
            tags = (session.contract.get("extensions") or {}).get("mw") or {}
            if isinstance(tags, dict):
                task_id = tags.get("task_id")
        build_and_post(
            session_id=session.session_id,
            player_id=pid,
            level_id=level_id,
            outcome=str(session.outcome or "success"),
            duration_sim_s=duration_sim_s,
            task_id=str(task_id) if task_id else None,
            display_name=session.player_name,
            space_id=session.space_id,
            route_kind=session.route_kind,
        )

    def _applied_cmd(self, mech: MechState) -> dict[str, Any] | None:
        """Control applied this tick (velocity + joint_targets), or None if idle."""
        if not mech.controlled:
            return None
        out: dict[str, Any] = {
            "entity_id": mech.entity_id,
            "control_mode": "velocity",
            "vx": mech.vx,
            "vy": mech.vy,
            "yaw_rate": mech.yaw_rate,
        }
        if mech.joint_targets:
            out["joint_targets"] = dict(mech.joint_targets)
        return out

    def _ensure_mj_model(self, contract: dict[str, Any]) -> Any:
        """Compile (or reuse) MjModel for contract.level_id.

        Cache key includes seed so D9 city-block regen rebuilds air walls.
        """
        level = str(contract.get("level_id") or "unknown")
        seed = contract.get("seed")
        cached = self._mj_models.get(level)
        if cached is not None and cached.get("seed") == seed:
            return cached["model"]
        if self.model_path is None:
            raise SystemExit("mujoco model_path missing")
        model = self._build_mujoco_world(self.model_path, contract)
        self._mj_models[level] = {"model": model, "seed": seed}
        return model

    def _build_mujoco_world(
        self, model_path: Path, contract: dict[str, Any] | None = None
    ) -> "mujoco.MjModel":
        """Build multi-mech world: ground + one attached chassis per spawn (F7).

        Starts from ``world_flat.xml`` (ground), strips the single included
        chassis, then attaches ``model_ref`` MJCF once per ``mech_spawns`` with
        prefix ``{entity_id}/``. Contract static_obstacles are appended as
        static box geoms (T2.3).
        """
        contract = contract if contract is not None else self.contract
        models_dir = model_path.parent
        spec = mujoco.MjSpec.from_file(str(model_path))
        # Drop the single-mech include so we can attach N prefixed copies.
        chassis = spec.worldbody.first_body()
        if chassis is not None and (chassis.name or "") == "chassis":
            spec.delete(chassis)

        spawns = list(contract.get("mech_spawns") or [])
        if not spawns:
            spawns = [{"id": "mech_player", "model_ref": "mechs/diffbot_planar.xml", "pose": {}}]

        for spawn in spawns:
            eid = str(spawn.get("id", "mech_player"))
            rel = str(spawn.get("model_ref") or "mechs/diffbot_planar.xml")
            mech_path = models_dir / rel
            if not mech_path.is_file():
                raise SystemExit(f"mech model_ref not found: {mech_path}")
            child = mujoco.MjSpec.from_file(str(mech_path))
            frame = spec.worldbody.add_frame(name=f"frame_{eid}", pos=[0.0, 0.0, 0.0])
            spec.attach(child, prefix=f"{eid}/", frame=frame)

        obstacles = contract.get("static_obstacles") or []
        appended = 0
        for ob in obstacles:
            if ob.get("physics_role", "mujoco_authoritative") != "mujoco_authoritative":
                continue
            if ob.get("shape") != "box":
                LOG.warning("obstacle %s: shape %r not supported, skipped", ob.get("id"), ob.get("shape"))
                continue
            pose = ob.get("pose") or {}
            quat = _yaw_to_quat(float(pose.get("yaw", 0.0)))
            geom = spec.worldbody.add_geom(
                name=str(ob.get("id", f"obstacle_{appended}")),
                type=mujoco.mjtGeom.mjGEOM_BOX,
                size=[float(s) / 2.0 for s in ob["size"]],
                pos=[float(pose.get("x", 0.0)), float(pose.get("y", 0.0)), float(pose.get("z", 0.0))],
                quat=[quat["qw"], quat["qx"], quat["qy"], quat["qz"]],
            )
            geom.contype = 1
            geom.conaffinity = 1
            geom.friction = list(OBSTACLE_FRICTION)
            appended += 1

        props = contract.get("dynamic_props") or []
        prop_n = self._append_dynamic_props(spec, props)
        # P1a: no sticky weld equalities — grasp relies on contact friction.
        LOG.info(
            "mujoco world F7: %d mechs attached, %d/%d static_obstacles, %d/%d dynamic_props, level=%s",
            len(spawns),
            appended,
            len(obstacles),
            prop_n,
            len(props),
            contract.get("level_id"),
        )
        return spec.compile()

    def _append_dynamic_props(self, spec: Any, props: list) -> int:
        """Add pushable/liftable boxes with freejoint into the MjSpec (V3c)."""
        added = 0
        for prop in props:
            if prop.get("physics_role", "mujoco_authoritative") != "mujoco_authoritative":
                continue
            if prop.get("shape", "box") != "box":
                LOG.warning("dynamic_prop %s: shape %r skipped", prop.get("id"), prop.get("shape"))
                continue
            pid = str(prop.get("id", f"prop_{added}"))
            half = [float(s) / 2.0 for s in prop["size"]]
            mass = float(prop.get("mass", 1.2))
            body = spec.worldbody.add_body(name=pid, pos=[0.0, 0.0, 0.0])
            body.add_freejoint(name=f"{pid}_free")
            geom = body.add_geom(
                name=f"{pid}_geom",
                type=mujoco.mjtGeom.mjGEOM_BOX,
                size=half,
                mass=mass,
            )
            geom.contype = 1
            geom.conaffinity = 1
            fr = float(prop.get("friction", OBSTACLE_FRICTION[0]))
            geom.friction = [fr, 0.1, 0.02]
            geom.rgba = [0.72, 0.48, 0.22, 1.0]
            added += 1
        return added

    def _append_grasp_welds(self, spec: Any, contract: dict[str, Any], props: list) -> None:
        """Add inactive weld equalities mech gripper_base ↔ each prop (V3c sticky grasp)."""
        for spawn in contract.get("mech_spawns") or []:
            eid = str(spawn.get("id", "mech_player"))
            model_ref = str(spawn.get("model_ref") or "")
            # City DiffBot has no gripper_base; only arm_gripper (etc.) get welds.
            if "gripper" not in model_ref and "arm" not in model_ref:
                continue
            for prop in props:
                if prop.get("physics_role", "mujoco_authoritative") != "mujoco_authoritative":
                    continue
                if prop.get("shape", "box") != "box":
                    continue
                pid = str(prop.get("id") or "")
                if not pid:
                    continue
                eq = spec.add_equality()
                eq.type = mujoco.mjtEq.mjEQ_WELD
                eq.objtype = mujoco.mjtObj.mjOBJ_BODY
                eq.name = f"grasp_{eid}_{pid}"
                eq.name1 = f"{eid}/gripper_base"
                eq.name2 = pid
                eq.active = False

    def _grasp_eq_map(
        self, model: Any, contract: dict[str, Any]
    ) -> dict[tuple[str, str], int]:
        """Resolve compiled equality ids for sticky grasp welds."""
        out: dict[tuple[str, str], int] = {}
        for spawn in contract.get("mech_spawns") or []:
            eid = str(spawn.get("id", "mech_player"))
            for prop in contract.get("dynamic_props") or []:
                pid = str(prop.get("id") or "")
                if not pid:
                    continue
                name = f"grasp_{eid}_{pid}"
                eq_id = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_EQUALITY, name)
                if eq_id >= 0:
                    out[(eid, pid)] = int(eq_id)
        return out

    def _update_sticky_grasps(self, room: Room) -> None:
        """Enable weld when gripper closed + near prop; kinematically attach while held."""
        if room.mj_data is None or room.mj_model is None or not room.grasp_eq:
            return
        data = room.mj_data
        model = room.mj_model
        for (eid, pid), eq_id in room.grasp_eq.items():
            mech = room.mechs.get(eid)
            prop = room.props.get(pid)
            if mech is None or prop is None or not isinstance(mech, MujocoMech):
                data.eq_active[eq_id] = 0
                continue
            if not _gripper_command_closed(mech, 0.02):
                data.eq_active[eq_id] = 0
                continue
            if (
                _prop_touches_gripper(model, data, eid, pid)
                or _gripper_prop_close(model, data, eid, pid, 0.18)
                or int(data.eq_active[eq_id]) == 1
            ):
                data.eq_active[eq_id] = 1
                # POC kinematic attach: keep prop glued to gripper_base while held.
                gid = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, f"{eid}/gripper_base")
                if gid >= 0:
                    data.qpos[prop._qadr + 0] = float(data.xpos[gid][0])
                    data.qpos[prop._qadr + 1] = float(data.xpos[gid][1])
                    data.qpos[prop._qadr + 2] = float(data.xpos[gid][2])
                    data.qpos[prop._qadr + 3] = float(data.xquat[gid][0])
                    data.qpos[prop._qadr + 4] = float(data.xquat[gid][1])
                    data.qpos[prop._qadr + 5] = float(data.xquat[gid][2])
                    data.qpos[prop._qadr + 6] = float(data.xquat[gid][3])
                    for i in range(6):
                        data.qvel[prop._dadr + i] = 0.0
                    mujoco.mj_forward(model, data)
                    prop.pull_state()
            else:
                data.eq_active[eq_id] = 0

    def _make_room_mechs(
        self, contract: dict[str, Any], mj_model: Any | None = None
    ) -> tuple[dict[str, MechState], dict[str, DynamicProp], Any, int, dict[tuple[str, str], int]]:
        """Instantiate contract mechs + props; MuJoCo uses one shared MjData (F7)."""
        mechs: dict[str, MechState] = {}
        props: dict[str, DynamicProp] = {}
        shared = None
        substeps = 1
        grasp_eq: dict[tuple[str, str], int] = {}
        model = mj_model
        if model is not None:
            shared = mujoco.MjData(model)
            substeps = max(1, int(round(DT / model.opt.timestep)))
            grasp_eq = self._grasp_eq_map(model, contract)
        for spawn in contract.get("mech_spawns") or []:
            eid = str(spawn.get("id", "mech_player"))
            pose = spawn.get("pose") or {}
            if shared is not None and model is not None:
                mech = MujocoMech(eid, model, shared, prefix=f"{eid}/")
            else:
                mech = MechState(eid)
            mech.reset_pose(pose)
            mech.controlled = False
            mech.vx = mech.vy = mech.yaw_rate = 0.0
            mechs[eid] = mech
        if not mechs:
            if shared is not None and model is not None:
                mech = MujocoMech("mech_player", model, shared, prefix="mech_player/")
            else:
                mech = MechState("mech_player")
            mech.reset_pose({})
            mechs["mech_player"] = mech
        if shared is not None and model is not None:
            for prop in contract.get("dynamic_props") or []:
                if prop.get("physics_role", "mujoco_authoritative") != "mujoco_authoritative":
                    continue
                if prop.get("shape", "box") != "box":
                    continue
                pid = str(prop["id"])
                dp = DynamicProp(
                    pid,
                    model,
                    shared,
                    body_name=pid,
                    joint_prefix=f"{pid}_",
                )
                dp.reset_pose(prop.get("pose") or {})
                props[pid] = dp
        return mechs, props, shared, substeps, grasp_eq

    def _leave_room(self, session: Session) -> None:
        """Detach session from its room; drop empty rooms."""
        room = session.room
        if room is None:
            return
        room.members.pop(session.session_id, None)
        if session.controlled_entity_id:
            mech = room.mechs.get(session.controlled_entity_id)
            if mech is not None:
                mech.controlled = False
                mech.vx = mech.vy = mech.yaw_rate = 0.0
        session.room = None
        session.controlled_entity_id = None
        session.joined = False
        if not room.members:
            self.rooms.pop(room.room_id, None)
            LOG.info("room=%s empty, removed", room.room_id)

    def _attach_occupant_profiles(
        self, room: Room, entities: list[dict[str, Any]]
    ) -> None:
        """Stamp display_name / accent onto occupied avatar entity_states (Hub)."""
        by_eid: dict[str, Session] = {}
        for member in room.members.values():
            if (
                member.joined
                and not member.closed
                and member.controlled_entity_id
            ):
                by_eid[member.controlled_entity_id] = member
        for ent in entities:
            eid = str(ent.get("entity_id") or "")
            occupant = by_eid.get(eid)
            if occupant is None:
                continue
            mw = ent.setdefault("extensions", {}).setdefault("mw", {})
            mw["display_name"] = occupant.player_name
            mw["occupied"] = True
            accent = occupant.profile.get("accent")
            if accent:
                mw["accent"] = str(accent)
            pid = occupant.profile.get("id")
            if pid:
                mw["profile_id"] = str(pid)

    async def handler(self, ws: ServerConnection) -> None:
        session_id = str(uuid.uuid4())
        session = Session(session_id=session_id, ws=ws, contract=self.contract)
        self.sessions[session_id] = session
        LOG.info("client connected session=%s", session_id)

        await send_json(
            ws,
            envelope(
                "hello",
                session_id=session_id,
                protocol_version=PROTOCOL_VERSION,
                payload={
                    "protocol_version": PROTOCOL_VERSION,
                    "dt": DT,
                    "sim_hz": SIM_HZ,
                    "state_hz": STATE_HZ,
                    "frame": self.contract.get("frame", "mineworld_zup_m"),
                    "features": self._feature_flags(),
                },
            ),
        )

        try:
            async for raw in ws:
                await self._on_message(session, raw)
        except websockets.ConnectionClosed:
            LOG.info("client closed session=%s", session_id)
        finally:
            session.closed = True
            outcome = session.outcome or "disconnect"
            self._close_recorder(session, outcome=outcome)
            self._leave_room(session)
            self.sessions.pop(session_id, None)

    async def _on_message(self, session: Session, raw: str | bytes) -> None:
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={"code": "INVALID_JSON", "message": "payload is not JSON"},
                ),
            )
            return

        msg_type = msg.get("type")
        payload = msg.get("payload") or {}

        if msg_type == "join":
            await self._handle_join(session, payload)
        elif msg_type == "cmd":
            await self._handle_cmd(session, payload)
        elif msg_type == "bye":
            session.closed = True
            outcome = session.outcome or "abort"
            self._close_recorder(session, outcome=outcome)
            self._leave_room(session)
            await session.ws.close()
        else:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "UNSUPPORTED_TYPE",
                        "message": f"unknown type: {msg_type}",
                    },
                ),
            )

    async def _handle_cmd(self, session: Session, payload: dict[str, Any]) -> None:
        """Accept cmds only for the session's assigned entity."""
        if str(payload.get("action") or "") == "presence_throttle":
            self._apply_presence_throttle(session, payload)
            return
        mech = session.mech
        if mech is None or not session.joined:
            return
        target = payload.get("entity_id")
        if target is not None and str(target) != mech.entity_id:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "NOT_YOUR_ENTITY",
                        "message": f"control limited to {mech.entity_id}",
                    },
                ),
            )
            return
        try:
            events = mech.apply_cmd(payload)
        except CmdRejected as err:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={"code": err.code, "message": err.message},
                ),
            )
            return
        session.pending_events.extend(events)

    def _apply_presence_throttle(
        self, session: Session, payload: dict[str, Any]
    ) -> None:
        """E9: Hub-only state downclock while visitor shell is open."""
        if session.room is None or not session.joined:
            return
        if not is_hub_contract(session.contract):
            return
        level = str(payload.get("level") or "full").strip().lower()
        mapping = {"full": 1, "low": 4, "paused": 0}
        session.presence_state_divisor = mapping.get(level, 1)
        mech = session.mech
        if session.presence_state_divisor == 0 and mech is not None:
            mech.vx = mech.vy = mech.yaw_rate = 0.0
        LOG.info(
            "session=%s presence_throttle=%s divisor=%d",
            session.session_id,
            level,
            session.presence_state_divisor,
        )

    def _should_send_state(self, session: Session, tick: int) -> bool:
        """Gate state frames per session (Hub presence_throttle)."""
        div = int(session.presence_state_divisor)
        if div == 1:
            return True
        slot = tick // STATE_EVERY_N_TICKS
        if div <= 0:
            # Keepalive ~0.5 Hz so the tab does not look disconnected.
            return slot % max(1, STATE_HZ // 2) == 0
        return slot % div == 0

    async def _handle_join(self, session: Session, payload: dict[str, Any]) -> None:
        self._maybe_reload_contract()
        level_id = str(payload.get("level_id") or self.contract.get("level_id") or "")
        if level_id in self.disabled_levels:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "LEVEL_DISABLED",
                        "message": f"level_id={level_id} disabled by admin (PL2)",
                    },
                ),
            )
            return
        contract_path = self.level_contracts.get(level_id)
        if contract_path is None:
            known = ", ".join(sorted(self.level_contracts)) or "(none)"
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "UNKNOWN_LEVEL",
                        "message": f"unknown level_id={level_id}; known=[{known}]",
                    },
                ),
            )
            return
        try:
            contract = load_contract(contract_path)
        except (OSError, json.JSONDecodeError) as exc:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "CONTRACT_LOAD",
                        "message": f"failed to load {contract_path}: {exc}",
                    },
                ),
            )
            return

        # Private room when omitted (= W2.3 isolation), except hub / city / race defaults.
        room_id = str(payload.get("room_id") or session.session_id)
        hub = is_hub_contract(contract)
        if hub:
            max_members = hub_max_members(contract)
            if not payload.get("room_id"):
                room_id = str(contract_mw(contract).get("default_room_id") or HUB_ROOM_ID)
        elif level_id == "demo_city":
            # Training yard: shared room `city`, max 5 (one mech each).
            max_members = CITY_ROOM_MAX
            if not payload.get("room_id"):
                room_id = CITY_ROOM_ID
        elif level_id == "demo_race":
            # Oval race: shared room `race`, max 6 (MuJoCo chassis).
            max_members = RACE_ROOM_MAX
            if not payload.get("room_id"):
                room_id = RACE_ROOM_ID
        elif room_id == CITY_ROOM_ID:
            max_members = CITY_ROOM_MAX
        elif room_id == RACE_ROOM_ID:
            max_members = RACE_ROOM_MAX
        elif room_id == DEMO_ROOM_ID:
            max_members = DEMO_ROOM_MAX
        else:
            max_members = 1

        player_name = str(payload.get("player_name") or "guest").strip() or "guest"
        profile: dict[str, Any] = {}
        space_id: str | None = None
        route_kind = "mineworld_level"
        join_ext = payload.get("extensions")
        if isinstance(join_ext, dict):
            join_mw = join_ext.get("mw")
            if isinstance(join_mw, dict):
                if isinstance(join_mw.get("profile"), dict):
                    profile = dict(join_mw["profile"])
                # E3: optional Space attribution from join.
                raw_sid = join_mw.get("space_id") or profile.get("space_id")
                if raw_sid is not None and str(raw_sid).strip():
                    space_id = str(raw_sid).strip()
                raw_rk = join_mw.get("route_kind")
                if raw_rk is not None and str(raw_rk).strip():
                    route_kind = str(raw_rk).strip()
                elif space_id:
                    route_kind = "pms_space"
        if profile.get("nickname"):
            player_name = str(profile["nickname"]).strip() or player_name
        # Hub: distinguish concurrent sessions (same account OK for now).
        if hub:
            tag = session.session_id.replace("-", "")[:4]
            player_name = f"{player_name} · {tag}"

        self._leave_room(session)

        room = self.rooms.get(room_id)
        if room is not None:
            room_level = str(room.contract.get("level_id") or "")
            if room_level != level_id:
                await send_json(
                    session.ws,
                    envelope(
                        "error",
                        session_id=session.session_id,
                        payload={
                            "code": "LEVEL_MISMATCH",
                            "message": f"room {room_id} is level={room_level}, got {level_id}",
                        },
                    ),
                )
                return
            active = [s for s in room.members.values() if s.joined and not s.closed]
            # Empty city room: rebuild so D9 seed regen air walls apply.
            if not active and (
                level_id == "demo_city"
                or room.contract.get("seed") != contract.get("seed")
            ):
                del self.rooms[room_id]
                room = None
            elif len(active) >= room.max_members:
                await send_json(
                    session.ws,
                    envelope(
                        "error",
                        session_id=session.session_id,
                        payload={
                            "code": "ROOM_FULL",
                            "message": f"room {room_id} is full (max {room.max_members})",
                        },
                    ),
                )
                return
        if room is None:
            # Hub is presence-only: never compile MuJoCo even if process uses --physics mujoco.
            mj_model = None
            if self.physics == "mujoco" and not hub:
                mj_model = self._ensure_mj_model(contract)
            mechs, props, mj_data, mj_substeps, grasp_eq = self._make_room_mechs(
                contract, mj_model
            )
            room = Room(
                room_id=room_id,
                contract=contract,
                mechs=mechs,
                props=props,
                max_members=max_members,
                mj_data=mj_data,
                mj_substeps=mj_substeps,
                grasp_eq=grasp_eq,
                mj_model=mj_model,
            )
            self.rooms[room_id] = room
            LOG.info(
                "room=%s level=%s max_members=%d mechs=%s props=%s shared_mj=%s hub=%s",
                room_id,
                level_id,
                max_members,
                list(room.mechs),
                list(room.props),
                mj_data is not None,
                hub,
            )

        entity_id = room.free_spawn_id()
        if entity_id is None:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "ROOM_FULL",
                        "message": f"no free mech spawn in room {room_id}",
                    },
                ),
            )
            return

        # First member into an existing empty room already reset via _make_room_mechs.
        # Public rooms (demo / hub): only reset when the room was empty.
        public_room = hub or room_id in (
            DEMO_ROOM_ID,
            CITY_ROOM_ID,
            RACE_ROOM_ID,
            HUB_ROOM_ID,
        )
        if (not public_room) or len([s for s in room.members.values() if s.joined]) == 0:
            spawn = next(
                (s for s in (room.contract.get("mech_spawns") or []) if s.get("id") == entity_id),
                None,
            )
            pose = (spawn or {}).get("pose") or {}
            room.mechs[entity_id].reset_pose(pose)
            room.mechs[entity_id].controlled = False
            room.mechs[entity_id].vx = room.mechs[entity_id].vy = room.mechs[entity_id].yaw_rate = 0.0
            if not public_room:
                room.tick = 0

        session.contract = room.contract
        session.level_id = level_id
        session.joined = True
        session.room = room
        session.controlled_entity_id = entity_id
        session.player_name = player_name
        session.profile = profile
        session.space_id = space_id
        session.route_kind = route_kind
        session.completed_objectives.clear()
        session.outcome = None
        session.pending_events.clear()
        room.members[session.session_id] = session

        self._close_recorder(session, outcome="abort")
        # Hub presence is not teleop capture — skip recordings.
        if self.record_dir is not None and not hub:
            software: dict[str, Any] = {"gateway_version": PROTOCOL_VERSION}
            if self.physics == "mujoco" and mujoco is not None:
                software["mujoco_version"] = getattr(mujoco, "__version__", "unknown")
            pid = str((profile or {}).get("id") or "").strip() or None
            session.recorder = SessionRecorder(
                self.record_dir,
                session_id=session.session_id,
                contract=room.contract,
                protocol_version=PROTOCOL_VERSION,
                dt=DT,
                sim_hz=SIM_HZ,
                state_hz=STATE_HZ,
                record_every_n_ticks=self.record_every_n_ticks,
                features=self._feature_flags(),
                software=software,
                player_id=pid,
                space_id=space_id,
                route_kind=route_kind,
            )

        entities = []
        claimed = {
            s.controlled_entity_id
            for s in room.members.values()
            if s.joined and not s.closed and s.controlled_entity_id
        }
        # Race: only show occupied slots (empty DiffBots stacked at spawn looked broken).
        race_only_claimed = level_id == "demo_race"
        for spawn in room.contract.get("mech_spawns") or []:
            sid = spawn["id"]
            if race_only_claimed and sid not in claimed:
                continue
            entities.append(
                {
                    "entity_id": sid,
                    "kind": "mech",
                    "model_ref": spawn.get("model_ref"),
                    "controllable": sid == entity_id,
                }
            )
        for obs in room.contract.get("static_obstacles") or []:
            entities.append(
                {
                    "entity_id": obs["id"],
                    "kind": "static_obstacle",
                    "controllable": False,
                }
            )
        for prop in room.contract.get("dynamic_props") or []:
            ent: dict[str, Any] = {
                "entity_id": prop["id"],
                "kind": "dynamic_prop",
                "controllable": False,
            }
            size = prop.get("size")
            if isinstance(size, list) and len(size) >= 3:
                ent["size"] = [float(size[0]), float(size[1]), float(size[2])]
            entities.append(ent)

        await send_json(
            session.ws,
            envelope(
                "scene",
                session_id=session.session_id,
                tick=room.tick,
                payload={
                    "level_id": level_id,
                    "contract_version": room.contract.get("contract_version", "0.1"),
                    "seed": room.contract.get("seed"),
                    "entities": entities,
                    "objectives": room.contract.get("objectives") or [],
                    "extensions": {
                        "mw": {
                            "room_id": room_id,
                            "controlled_entity_id": entity_id,
                        }
                    },
                },
            ),
        )
        LOG.info(
            "session=%s joined level=%s room=%s entity=%s",
            session.session_id,
            level_id,
            room_id,
            entity_id,
        )

    async def sim_loop(self) -> None:
        """Advance each Room at SIM_HZ; broadcast state at STATE_HZ to members."""
        while True:
            await asyncio.sleep(DT)
            for room in list(self.rooms.values()):
                members = [s for s in room.members.values() if s.joined and not s.closed]
                if not members:
                    continue
                room.step_physics(DT)
                # P1a: friction grasp only (no sticky kinematic weld).
                room.tick += 1
                claimed = {
                    s.controlled_entity_id
                    for s in members
                    if s.controlled_entity_id
                }
                race_only = str(room.contract.get("level_id") or "") == "demo_race"
                mech_states = []
                for m in room.mechs.values():
                    if race_only and m.entity_id not in claimed:
                        continue
                    mech_states.append(m.to_entity_state())
                entities = mech_states + [
                    p.to_entity_state() for p in room.props.values()
                ]
                self._attach_occupant_profiles(room, entities)
                state_payload = {
                    "kind": "full",
                    "entities": entities,
                }
                for session in members:
                    tick_events = list(session.pending_events)
                    session.pending_events.clear()
                    objective_events = evaluate_objectives(session)
                    objective_events.extend(evaluate_time_limit(session))
                    if objective_events:
                        duration = float(room.tick) * DT
                        level_id = str(
                            session.level_id or session.contract.get("level_id") or ""
                        )
                        for ev in objective_events:
                            et = ev.get("event_type")
                            detail = ev.get("detail")
                            if not isinstance(detail, dict):
                                detail = {}
                                ev["detail"] = detail
                            detail.setdefault("level_id", level_id)
                            if et == "objective_complete":
                                # Terminal place only (grasp_lift / milestone skip score).
                                if detail.get("kind") in ("grasp_lift", "milestone"):
                                    continue
                                if session.outcome != "success":
                                    continue
                                if session.recorder is not None:
                                    oid = str(ev.get("objective_id") or "")
                                    if oid:
                                        session.recorder.set_task_id(oid)
                                pts = compute_points(
                                    level_id=level_id,
                                    outcome="success",
                                    duration_sim_s=duration,
                                )
                                detail["points"] = pts
                                self._report_score(session, duration)
                            elif et == "objective_failed":
                                if session.recorder is not None:
                                    oid = str(ev.get("objective_id") or "")
                                    if oid:
                                        session.recorder.set_task_id(oid)
                                detail["points"] = 0
                                self._report_score(session, duration)
                        tick_events.extend(objective_events)
                        if session.recorder is not None and session.outcome:
                            session.recorder.set_outcome(session.outcome)
                    if session.recorder is not None and session.mech is not None:
                        session.recorder.write_frame(
                            tick=room.tick,
                            cmd=self._applied_cmd(session.mech),
                            state=state_payload,
                            events=tick_events,
                        )
                    try:
                        for ev in tick_events:
                            await send_json(
                                session.ws,
                                envelope(
                                    "event",
                                    session_id=session.session_id,
                                    tick=room.tick,
                                    payload=ev,
                                ),
                            )
                        if (
                            room.tick % STATE_EVERY_N_TICKS == 0
                            and self._should_send_state(session, room.tick)
                        ):
                            await send_json(
                                session.ws,
                                envelope(
                                    "state",
                                    session_id=session.session_id,
                                    tick=room.tick,
                                    payload=state_payload,
                                ),
                            )
                    except websockets.ConnectionClosed:
                        session.closed = True
                    except Exception:
                        LOG.exception(
                            "sim_loop send failed session=%s", session.session_id
                        )
                        session.closed = True


async def run(
    host: str,
    port: int,
    contract_path: Path,
    physics: str,
    model_path: Path | None,
    record_dir: Path | None,
    record_every_n_ticks: int,
    admin_host: str = "127.0.0.1",
    admin_port: int = 8770,
) -> None:
    contract = load_contract(contract_path)
    gateway = EchoGateway(
        contract,
        physics=physics,
        model_path=model_path,
        record_dir=record_dir,
        record_every_n_ticks=record_every_n_ticks,
        contract_path=contract_path,
    )
    try:
        from admin_http import start_admin_http

        start_admin_http(gateway, host=admin_host, port=admin_port)
    except Exception:
        LOG.exception("admin HTTP failed to start (WS still runs)")
    asyncio.create_task(gateway.sim_loop())

    LOG.info(
        "listening ws://%s:%s contract=%s level=%s physics=%s record_dir=%s admin_http=%s:%s",
        host,
        port,
        contract_path,
        contract.get("level_id"),
        physics,
        record_dir,
        admin_host,
        admin_port,
    )
    try:
        async with serve(gateway.handler, host, port):
            await asyncio.Future()
    except OSError as exc:
        if getattr(exc, "errno", None) == 48 or "address already in use" in str(exc).lower():
            LOG.error(
                "port %s already in use. Free it with:\n"
                "  lsof -nP -iTCP:%s -sTCP:LISTEN\n"
                "  kill <PID>\n"
                "Or start on another port:\n"
                "  python gateway/echo_server.py --port 8766",
                port,
                port,
            )
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description="MineWorld POC-A echo gateway")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--contract",
        type=Path,
        default=DEFAULT_CONTRACT,
        help="Path to scene contract JSON",
    )
    parser.add_argument(
        "--physics",
        choices=["fake", "mujoco"],
        default="fake",
        help="Physics backend: fake (POC-A fallback) or mujoco (real sim)",
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=REPO_ROOT / "mujoco" / "models" / "world_flat.xml",
        help="MJCF model path (required for --physics mujoco)",
    )
    parser.add_argument(
        "--record-dir",
        type=Path,
        default=DEFAULT_RECORD_DIR,
        help="Session recording root (header.json + frames.jsonl per session)",
    )
    parser.add_argument(
        "--no-record",
        action="store_true",
        help="Disable session recording",
    )
    parser.add_argument(
        "--record-every-n-ticks",
        type=int,
        default=1,
        help="Downsample recording (1 = every sim tick)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument(
        "--admin-host",
        default="127.0.0.1",
        help="PL2 admin HTTP bind (rooms/contracts)",
    )
    parser.add_argument(
        "--admin-port",
        type=int,
        default=8770,
        help="PL2 admin HTTP port (0=disable)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    record_dir = None if args.no_record else args.record_dir
    try:
        asyncio.run(
            run(
                args.host,
                args.port,
                args.contract,
                args.physics,
                args.model,
                record_dir,
                args.record_every_n_ticks,
                admin_host=args.admin_host,
                admin_port=args.admin_port,
            )
        )
    except KeyboardInterrupt:
        LOG.info("shutdown")


if __name__ == "__main__":
    main()
