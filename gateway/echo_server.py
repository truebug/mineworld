"""MineWorld POC WebSocket gateway.

Physics backends (--physics):
  fake   - in-process kinematic integrator (POC-A; regression fallback)
  mujoco - real MuJoCo sim (POC-B / T2.2): cmd -> ctrl, state <- qpos.
           Contract static_obstacles are appended as static geoms (T2.3).

Rooms (W2.3 / W3):
  join.payload.room_id omitted → private room (= session_id), one member.
  room_id "demo" → shared room, max 2 members; each mech has its own MjData
  (same MjModel). State fans out to all members. No inter-mech collision yet.

Recording (T2.5): on join, writes recordings/sessions/<id>/header.json + frames.jsonl.
Joints (T2.6): entity_state includes joints / joint_vels for slide_x/y + yaw_z.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import math
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import websockets
from websockets.asyncio.server import ServerConnection, serve

from recorder import SessionRecorder

try:  # optional: only --physics mujoco needs it
    import mujoco
except ImportError:  # pragma: no cover
    mujoco = None

LOG = logging.getLogger("mineworld.gateway")

PROTOCOL_VERSION = "0.1"
DT = 0.02
SIM_HZ = 50
STATE_HZ = 20
STATE_EVERY_N_TICKS = max(1, SIM_HZ // STATE_HZ)
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONTRACT = REPO_ROOT / "examples" / "contracts" / "tutorial_01.json"
DEFAULT_RECORD_DIR = REPO_ROOT / "recordings" / "sessions"
OBSTACLE_FRICTION = (0.8, 0.02, 0.01)  # aligned with ground/chassis defaults
DEMO_ROOM_ID = "demo"
DEMO_ROOM_MAX = 2


def _yaw_to_quat(yaw: float) -> dict[str, float]:
    """Z-up yaw (radians) → wxyz quaternion."""
    half = 0.5 * yaw
    return {"qw": math.cos(half), "qx": 0.0, "qy": 0.0, "qz": math.sin(half)}


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

    def reset_pose(self, pose: dict[str, Any]) -> None:
        self.x = float(pose.get("x", 0.0))
        self.y = float(pose.get("y", 0.0))
        self.z = float(pose.get("z", 0.5))
        self.yaw = float(pose.get("yaw", 0.0))

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

        mode = payload.get("control_mode", "velocity")
        if mode == "velocity" and self.controlled:
            self.vx = float(payload.get("vx", 0.0))
            self.vy = float(payload.get("vy", 0.0))
            self.yaw_rate = float(payload.get("yaw_rate", 0.0))
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
    Each mech owns its own MjData (W2.3 / W3); no inter-mech collision yet.
    """

    def __init__(self, entity_id: str, model: "mujoco.MjModel", data: "mujoco.MjData") -> None:
        super().__init__(entity_id)
        self._model = model
        self._data = data
        jnt = lambda n: mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, n)
        self._qx = model.jnt_qposadr[jnt("slide_x")]
        self._qy = model.jnt_qposadr[jnt("slide_y")]
        self._qyaw = model.jnt_qposadr[jnt("yaw_z")]
        self._dx = model.jnt_dofadr[jnt("slide_x")]
        self._dy = model.jnt_dofadr[jnt("slide_y")]
        self._dyaw = model.jnt_dofadr[jnt("yaw_z")]
        self._substeps = max(1, int(round(DT / model.opt.timestep)))
        self.reset_pose({})

    def reset_pose(self, pose: dict[str, Any]) -> None:
        super().reset_pose(pose)
        if not hasattr(self, "_data"):
            return
        self._data.qpos[self._qx] = self.x
        self._data.qpos[self._qy] = self.y
        self._data.qpos[self._qyaw] = self.yaw
        self._data.qvel[:] = 0.0
        self._data.ctrl[:] = 0.0
        mujoco.mj_forward(self._model, self._data)

    def step(self, dt: float) -> None:
        if not self.controlled:
            self._data.ctrl[:] = 0.0
        else:
            yaw = float(self._data.qpos[self._qyaw])
            c, s = math.cos(yaw), math.sin(yaw)
            self._data.ctrl[0] = c * self.vx - s * self.vy
            self._data.ctrl[1] = s * self.vx + c * self.vy
            self._data.ctrl[2] = self.yaw_rate
        for _ in range(self._substeps):
            mujoco.mj_step(self._model, self._data)
        d = self._data
        self.x = float(d.qpos[self._qx])
        self.y = float(d.qpos[self._qy])
        # qpos is the kinematic truth (slide x/y + hinge z); xpos needs a
        # forward pass to re-sync after mj_step for the same tick.
        mujoco.mj_forward(self._model, d)
        self.z = float(d.xpos[mujoco.mj_name2id(self._model, mujoco.mjtObj.mjOBJ_BODY, "chassis")][2])
        self.yaw = float(d.qpos[self._qyaw])

    def to_entity_state(self) -> dict[str, Any]:
        q = _yaw_to_quat(self.yaw)
        d = self._data
        return {
            "entity_id": self.entity_id,
            "base_pose": {"x": self.x, "y": self.y, "z": self.z, "yaw": self.yaw, **q},
            "velocities": {
                "vx": float(d.qvel[self._dx]),
                "vy": float(d.qvel[self._dy]),
                "vz": 0.0,
            },
            "joints": {
                "slide_x": float(d.qpos[self._qx]),
                "slide_y": float(d.qpos[self._qy]),
                "yaw_z": float(d.qpos[self._qyaw]),
            },
            "joint_vels": {
                "slide_x": float(d.qvel[self._dx]),
                "slide_y": float(d.qvel[self._dy]),
                "yaw_z": float(d.qvel[self._dyaw]),
            },
        }


@dataclass
class Room:
    """Logical shared world: mechs + members; one tick for all members."""

    room_id: str
    contract: dict[str, Any]
    mechs: dict[str, MechState] = field(default_factory=dict)
    members: dict[str, Session] = field(default_factory=dict)
    tick: int = 0
    max_members: int = 1

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

    @property
    def mech(self) -> MechState | None:
        """Assigned mech in the current room, if any."""
        if self.room is None or not self.controlled_entity_id:
            return None
        return self.room.mechs.get(self.controlled_entity_id)


def load_contract(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def point_in_aabb(x: float, y: float, z: float, mn: list[float], mx: list[float]) -> bool:
    """Return True if point lies inside an axis-aligned box (inclusive)."""
    return (
        float(mn[0]) <= x <= float(mx[0])
        and float(mn[1]) <= y <= float(mx[1])
        and float(mn[2]) <= z <= float(mx[2])
    )


def evaluate_objectives(session: Session) -> list[dict[str, Any]]:
    """Gateway-authoritative objective checks (T3.1). Emit each objective once."""
    events: list[dict[str, Any]] = []
    mech = session.mech
    if mech is None:
        return events
    triggers = {t["id"]: t for t in (session.contract.get("triggers") or []) if t.get("id")}
    for obj in session.contract.get("objectives") or []:
        obj_id = obj.get("id")
        if not obj_id or obj_id in session.completed_objectives:
            continue
        if obj.get("type") != "reach_region":
            continue
        trig = triggers.get(obj.get("target"))
        if not trig or trig.get("type") != "aabb":
            continue
        mn = trig.get("min") or []
        mx = trig.get("max") or []
        if len(mn) < 3 or len(mx) < 3:
            continue
        if not point_in_aabb(mech.x, mech.y, mech.z, mn, mx):
            continue
        session.completed_objectives.add(obj_id)
        session.outcome = "success"
        events.append(
            {
                "event_type": "objective_complete",
                "objective_id": obj_id,
                "entity_id": mech.entity_id,
                "detail": {"trigger_id": trig["id"]},
            }
        )
        LOG.info(
            "session=%s objective_complete id=%s at (%.2f, %.2f, %.2f)",
            session.session_id,
            obj_id,
            mech.x,
            mech.y,
            mech.z,
        )
    return events


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
    ) -> None:
        self.contract = contract
        self.sessions: dict[str, Session] = {}
        self.rooms: dict[str, Room] = {}
        self.physics = physics
        self.record_dir = record_dir
        self.record_every_n_ticks = record_every_n_ticks
        self.mj_model = None
        if physics == "mujoco":
            if mujoco is None:
                raise SystemExit("mujoco not installed: pip install mujoco==3.6.0")
            if model_path is None:
                raise SystemExit("--physics mujoco requires --model")
            self.mj_model = self._build_mujoco_world(model_path)

    def _feature_flags(self) -> list[str]:
        """Return hello/recording feature tags for the active physics backend."""
        return ["fake_kinematics" if self.physics == "fake" else "mujoco"]

    def _close_recorder(self, session: Session, outcome: str) -> None:
        """Finalize session recording if one is open."""
        if session.recorder is None:
            return
        try:
            session.recorder.close(outcome=outcome)
        except Exception:
            LOG.exception("recorder close failed session=%s", session.session_id)
        session.recorder = None

    def _applied_cmd(self, mech: MechState) -> dict[str, Any] | None:
        """Control applied this tick (velocity setpoints), or None if idle."""
        if not mech.controlled:
            return None
        return {
            "entity_id": mech.entity_id,
            "control_mode": "velocity",
            "vx": mech.vx,
            "vy": mech.vy,
            "yaw_rate": mech.yaw_rate,
        }

    def _build_mujoco_world(self, model_path: Path) -> "mujoco.MjModel":
        """Load base MJCF and append contract static_obstacles as static geoms.

        Only shape=box is supported at POC stage. Contract size is the full
        edge length; MJCF geom size is the half-extent. Obstacles with a
        physics_role other than mujoco_authoritative are viewer-only and
        skipped here.
        """
        spec = mujoco.MjSpec.from_file(str(model_path))
        obstacles = self.contract.get("static_obstacles") or []
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
            # <default> in box_mech.xml does not reach geoms added via MjSpec.
            geom.contype = 1
            geom.conaffinity = 1
            geom.friction = list(OBSTACLE_FRICTION)
            appended += 1
        LOG.info(
            "mujoco world: %d/%d static_obstacles appended from contract level=%s",
            appended,
            len(obstacles),
            self.contract.get("level_id"),
        )
        return spec.compile()

    def _make_mech(self, entity_id: str, pose: dict[str, Any]) -> MechState:
        """Create one mech; MuJoCo path allocates a fresh MjData per mech."""
        if self.mj_model is not None:
            data = mujoco.MjData(self.mj_model)
            mech = MujocoMech(entity_id, self.mj_model, data)
        else:
            mech = MechState(entity_id)
        mech.reset_pose(pose)
        mech.controlled = False
        mech.vx = mech.vy = mech.yaw_rate = 0.0
        return mech

    def _make_room_mechs(self) -> dict[str, MechState]:
        """Instantiate all contract mech_spawns for a new Room."""
        mechs: dict[str, MechState] = {}
        for spawn in self.contract.get("mech_spawns") or []:
            eid = str(spawn.get("id", "mech_player"))
            mechs[eid] = self._make_mech(eid, spawn.get("pose") or {})
        if not mechs:
            mechs["mech_player"] = self._make_mech("mech_player", {})
        return mechs

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
        events = mech.apply_cmd(payload)
        session.pending_events.extend(events)

    async def _handle_join(self, session: Session, payload: dict[str, Any]) -> None:
        level_id = payload.get("level_id") or self.contract.get("level_id")
        expected = self.contract.get("level_id")
        if level_id != expected:
            await send_json(
                session.ws,
                envelope(
                    "error",
                    session_id=session.session_id,
                    payload={
                        "code": "UNKNOWN_LEVEL",
                        "message": f"POC only supports {expected}, got {level_id}",
                    },
                ),
            )
            return

        # Private room when omitted (= W2.3 isolation).
        room_id = str(payload.get("room_id") or session.session_id)
        max_members = DEMO_ROOM_MAX if room_id == DEMO_ROOM_ID else 1

        self._leave_room(session)

        room = self.rooms.get(room_id)
        if room is None:
            room = Room(
                room_id=room_id,
                contract=self.contract,
                mechs=self._make_room_mechs(),
                max_members=max_members,
            )
            self.rooms[room_id] = room
            LOG.info("room=%s created max_members=%d mechs=%s", room_id, max_members, list(room.mechs))
        else:
            active = [s for s in room.members.values() if s.joined and not s.closed]
            if len(active) >= room.max_members:
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
        # Re-join private room: reset that mech to spawn pose.
        if room_id != DEMO_ROOM_ID or len([s for s in room.members.values() if s.joined]) == 0:
            spawn = next(
                (s for s in (self.contract.get("mech_spawns") or []) if s.get("id") == entity_id),
                None,
            )
            pose = (spawn or {}).get("pose") or {}
            room.mechs[entity_id].reset_pose(pose)
            room.mechs[entity_id].controlled = False
            room.mechs[entity_id].vx = room.mechs[entity_id].vy = room.mechs[entity_id].yaw_rate = 0.0
            if room_id != DEMO_ROOM_ID:
                room.tick = 0

        session.level_id = level_id
        session.joined = True
        session.room = room
        session.controlled_entity_id = entity_id
        session.completed_objectives.clear()
        session.outcome = None
        session.pending_events.clear()
        room.members[session.session_id] = session

        self._close_recorder(session, outcome="abort")
        if self.record_dir is not None:
            software: dict[str, Any] = {"gateway_version": PROTOCOL_VERSION}
            if self.physics == "mujoco" and mujoco is not None:
                software["mujoco_version"] = getattr(mujoco, "__version__", "unknown")
            session.recorder = SessionRecorder(
                self.record_dir,
                session_id=session.session_id,
                contract=self.contract,
                protocol_version=PROTOCOL_VERSION,
                dt=DT,
                sim_hz=SIM_HZ,
                state_hz=STATE_HZ,
                record_every_n_ticks=self.record_every_n_ticks,
                features=self._feature_flags(),
                software=software,
            )

        entities = []
        for spawn in self.contract.get("mech_spawns") or []:
            sid = spawn["id"]
            entities.append(
                {
                    "entity_id": sid,
                    "kind": "mech",
                    "model_ref": spawn.get("model_ref"),
                    "controllable": sid == entity_id,
                }
            )
        for obs in self.contract.get("static_obstacles") or []:
            entities.append(
                {
                    "entity_id": obs["id"],
                    "kind": "static_obstacle",
                    "controllable": False,
                }
            )

        await send_json(
            session.ws,
            envelope(
                "scene",
                session_id=session.session_id,
                tick=room.tick,
                payload={
                    "level_id": level_id,
                    "contract_version": self.contract.get("contract_version", "0.1"),
                    "seed": self.contract.get("seed"),
                    "entities": entities,
                    "objectives": self.contract.get("objectives") or [],
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
                for mech in room.mechs.values():
                    mech.step(DT)
                room.tick += 1
                state_payload = {
                    "kind": "full",
                    "entities": [m.to_entity_state() for m in room.mechs.values()],
                }
                for session in members:
                    tick_events = list(session.pending_events)
                    session.pending_events.clear()
                    objective_events = evaluate_objectives(session)
                    if objective_events:
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
                        if room.tick % STATE_EVERY_N_TICKS == 0:
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
) -> None:
    contract = load_contract(contract_path)
    gateway = EchoGateway(
        contract,
        physics=physics,
        model_path=model_path,
        record_dir=record_dir,
        record_every_n_ticks=record_every_n_ticks,
    )
    asyncio.create_task(gateway.sim_loop())

    LOG.info(
        "listening ws://%s:%s contract=%s level=%s physics=%s record_dir=%s",
        host,
        port,
        contract_path,
        contract.get("level_id"),
        physics,
        record_dir,
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
            )
        )
    except KeyboardInterrupt:
        LOG.info("shutdown")


if __name__ == "__main__":
    main()
