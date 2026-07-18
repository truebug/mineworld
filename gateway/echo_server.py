"""MineWorld POC WebSocket gateway.

Physics backends (--physics):
  fake   - in-process kinematic integrator (POC-A; regression fallback)
  mujoco - real MuJoCo sim (POC-B / T2.2): cmd -> ctrl, state <- qpos
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
DEFAULT_CONTRACT = (
    Path(__file__).resolve().parents[1] / "examples" / "contracts" / "tutorial_01.json"
)


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
        }


class MujocoMech(MechState):
    """MuJoCo-backed mech. cmd writes ctrl, state reads MjData.

    The chassis slide joints translate in the parent (world) frame (they
    compose before the hinge), so the body-frame velocity command must be
    rotated by the current yaw — same math as the fake integrator.
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
        }


@dataclass
class Session:
    session_id: str
    ws: ServerConnection
    contract: dict[str, Any]
    tick: int = 0
    joined: bool = False
    level_id: str | None = None
    mech: MechState = field(default_factory=lambda: MechState("mech_player"))
    pending_events: list[dict[str, Any]] = field(default_factory=list)
    closed: bool = False

    def reset_from_contract(self) -> None:
        spawns = self.contract.get("mech_spawns") or []
        if not spawns:
            return
        spawn = spawns[0]
        pose = spawn.get("pose") or {}
        entity_id = spawn.get("id", "mech_player")
        if self.mech is None or self.mech.entity_id != entity_id:
            self.mech = MechState(entity_id=entity_id)
        self.mech.reset_pose(pose)
        self.mech.controlled = False
        self.mech.vx = self.mech.vy = self.mech.yaw_rate = 0.0


def load_contract(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


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
    """Single-process POC gateway: kinematic integrator + WS fan-out."""

    def __init__(
        self,
        contract: dict[str, Any],
        physics: str = "fake",
        model_path: Path | None = None,
    ) -> None:
        self.contract = contract
        self.sessions: dict[str, Session] = {}
        self.physics = physics
        self.mj_model = None
        self.mj_data = None
        if physics == "mujoco":
            if mujoco is None:
                raise SystemExit("mujoco not installed: pip install mujoco==3.6.0")
            if model_path is None:
                raise SystemExit("--physics mujoco requires --model")
            self.mj_model = mujoco.MjModel.from_xml_path(str(model_path))
            # Single shared MjData: fine for POC single-client; multi-session
            # needs one MjData per session (or a worker pool).
            self.mj_data = mujoco.MjData(self.mj_model)

    async def handler(self, ws: ServerConnection) -> None:
        session_id = str(uuid.uuid4())
        session = Session(session_id=session_id, ws=ws, contract=self.contract)
        if self.mj_data is not None:
            spawns = self.contract.get("mech_spawns") or [{}]
            session.mech = MujocoMech(
                spawns[0].get("id", "mech_player"), self.mj_model, self.mj_data
            )
        session.reset_from_contract()
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
                    "features": ["fake_kinematics" if self.physics == "fake" else "mujoco"],
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
            events = session.mech.apply_cmd(payload)
            session.pending_events.extend(events)
        elif msg_type == "bye":
            session.closed = True
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

        session.level_id = level_id
        session.joined = True
        session.tick = 0
        session.reset_from_contract()

        entities = []
        for spawn in self.contract.get("mech_spawns") or []:
            entities.append(
                {
                    "entity_id": spawn["id"],
                    "kind": "mech",
                    "model_ref": spawn.get("model_ref"),
                    "controllable": True,
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
                tick=0,
                payload={
                    "level_id": level_id,
                    "contract_version": self.contract.get("contract_version", "0.1"),
                    "seed": self.contract.get("seed"),
                    "entities": entities,
                    "objectives": self.contract.get("objectives") or [],
                },
            ),
        )
        LOG.info("session=%s joined level=%s", session.session_id, level_id)

    async def sim_loop(self) -> None:
        """Advance all joined sessions at SIM_HZ; broadcast state at STATE_HZ."""
        while True:
            await asyncio.sleep(DT)
            for session in list(self.sessions.values()):
                if session.closed or not session.joined:
                    continue
                session.mech.step(DT)
                session.tick += 1
                try:
                    for ev in session.pending_events:
                        await send_json(
                            session.ws,
                            envelope(
                                "event",
                                session_id=session.session_id,
                                tick=session.tick,
                                payload=ev,
                            ),
                        )
                    session.pending_events.clear()

                    if session.tick % STATE_EVERY_N_TICKS == 0:
                        await send_json(
                            session.ws,
                            envelope(
                                "state",
                                session_id=session.session_id,
                                tick=session.tick,
                                payload={
                                    "kind": "full",
                                    "entities": [session.mech.to_entity_state()],
                                },
                            ),
                        )
                except websockets.ConnectionClosed:
                    # Client vanished between the liveness check above and the
                    # send; the handler's finally block removes the session.
                    # Never let a dead session kill the loop for the others.
                    session.closed = True
                except Exception:
                    LOG.exception(
                        "sim_loop send failed session=%s", session.session_id
                    )
                    session.closed = True


async def run(host: str, port: int, contract_path: Path, physics: str, model_path: Path | None) -> None:
    contract = load_contract(contract_path)
    gateway = EchoGateway(contract, physics=physics, model_path=model_path)
    asyncio.create_task(gateway.sim_loop())

    LOG.info(
        "listening ws://%s:%s contract=%s level=%s physics=%s",
        host,
        port,
        contract_path,
        contract.get("level_id"),
        physics,
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
        default=Path(__file__).resolve().parents[1] / "mujoco" / "models" / "world_flat.xml",
        help="MJCF model path (required for --physics mujoco)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    try:
        asyncio.run(run(args.host, args.port, args.contract, args.physics, args.model))
    except KeyboardInterrupt:
        LOG.info("shutdown")


if __name__ == "__main__":
    main()
