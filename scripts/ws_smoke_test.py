"""Smoke-test MineWorld gateway: hello → join → take_control → velocity → state.

Optional --expect-objective: closed-loop drive demo_city until objective_complete.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import sys
import uuid
from pathlib import Path

import websockets

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from city_drive_helper import (  # noqa: E402
    entity_xy,
    entity_xy_yaw,
    load_city_finish,
    load_race_finish,
    load_race_waypoints,
    manhattan_cmd,
    race_chase_cmd,
)


async def _send_vel(
    ws, session_id: str, vx: float, vy: float = 0.0, yaw_rate: float = 0.0
) -> None:
    """Send a velocity command for mech_player."""
    await ws.send(
        json.dumps(
            {
                "type": "cmd",
                "session_id": session_id,
                "payload": {
                    "entity_id": "mech_player",
                    "control_mode": "velocity",
                    "vx": vx,
                    "vy": vy,
                    "yaw_rate": yaw_rate,
                },
            }
        )
    )


async def smoke(
    url: str,
    seconds: float,
    *,
    level_id: str,
    expect_objective: bool,
    yaw_rate: float,
) -> int:
    async with websockets.connect(url) as ws:
        hello_raw = await asyncio.wait_for(ws.recv(), timeout=5)
        hello = json.loads(hello_raw)
        assert hello.get("type") == "hello", hello
        session_id = hello["session_id"]
        print("hello ok", session_id, hello["payload"])

        # Private room so shared city/race occupancy does not block smoke.
        join_payload: dict = {"level_id": level_id, "player_name": "smoke"}
        if level_id in ("demo_city", "demo_race"):
            join_payload["room_id"] = f"smoke-{uuid.uuid4().hex[:8]}"

        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": session_id,
                    "payload": join_payload,
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene
        print("scene ok", scene["payload"]["level_id"], len(scene["payload"]["entities"]))

        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": session_id,
                    "payload": {"action": "take_control", "entity_id": "mech_player"},
                }
            )
        )

        race_wps: list[tuple[float, float]] = []
        race_wp_i = 0
        race_stuck_n = 0
        race_last_xy = (0.0, 0.0)
        race_stuck_t0 = 0.0
        if level_id == "demo_race":
            _sx, _sy, finish_x, finish_y = load_race_finish()
            turn_x = finish_x
            if expect_objective:
                race_wps = load_race_waypoints()
                print(
                    f"note: demo_race chase {len(race_wps)} wps → finish=({finish_x:.1f},{finish_y:.1f})"
                )
        else:
            _sx, _sy, finish_x, finish_y = load_city_finish()
            turn_x = finish_x
        if expect_objective and level_id == "demo_city":
            print(
                f"note: demo_city Manhattan → finish=({finish_x:.1f},{finish_y:.1f})"
            )
        elif expect_objective and level_id != "demo_race":
            await _send_vel(ws, session_id, 1.0, 0.0, yaw_rate)
        elif not expect_objective:
            spd = 1.0
            await _send_vel(ws, session_id, spd, 0.0, yaw_rate)

        saw_take = False
        saw_objective = False
        saw_state = False
        saw_joints = False
        saw_wheels = False
        first_x = None
        last_x = None
        last_cmd = 0.0
        deadline = asyncio.get_event_loop().time() + seconds
        while asyncio.get_event_loop().time() < deadline:
            raw = await asyncio.wait_for(ws.recv(), timeout=5)
            msg = json.loads(raw)
            if msg.get("type") == "event":
                et = msg["payload"].get("event_type")
                print("event", et, msg["payload"].get("objective_id", ""))
                if et == "player_take_control":
                    saw_take = True
                if et == "objective_complete":
                    oid = str(msg["payload"].get("objective_id", ""))
                    detail = msg["payload"].get("detail") or {}
                    kind = str(detail.get("kind", "")) if isinstance(detail, dict) else ""
                    # Race: only terminal finish counts (CP milestones fire earlier).
                    if level_id == "demo_race" and (
                        kind == "milestone" or oid != "obj_race_finish"
                    ):
                        print("event", et, oid, "(milestone — continue)")
                        continue
                    saw_objective = True
                    if expect_objective:
                        break
            elif msg.get("type") == "state":
                saw_state = True
                entities = msg["payload"]["entities"]
                ent = next(
                    (e for e in entities if e.get("entity_id") == "mech_player"),
                    entities[0],
                )
                last_x = ent["base_pose"]["x"]
                if first_x is None:
                    first_x = last_x
                joints = ent.get("joints") or {}
                if "slide_x" in joints and "slide_y" in joints and "yaw_z" in joints:
                    saw_joints = True
                if any(k.startswith("wheel_") for k in joints) or "root" in joints:
                    saw_joints = True
                if "left_wheel_joint" in joints and "right_wheel_joint" in joints:
                    saw_wheels = True
                if any(k.startswith("wheel_") for k in joints):
                    saw_wheels = True
                print(
                    f"state tick={msg['tick']} x={ent['base_pose']['x']:.3f} "
                    f"y={ent['base_pose']['y']:.3f} yaw={ent['base_pose']['yaw']:.3f} "
                    f"joints={bool(joints)} wheels={saw_wheels}"
                )
                if expect_objective and level_id == "demo_city":
                    now = asyncio.get_event_loop().time()
                    if now - last_cmd >= 0.05:
                        x, y = entity_xy(msg["payload"])
                        vx, vy = manhattan_cmd(x, y, finish_x, finish_y, turn_x=turn_x)
                        await _send_vel(ws, session_id, vx, vy, 0.0)
                        last_cmd = now
                elif expect_objective and level_id == "demo_race" and race_wps:
                    now = asyncio.get_event_loop().time()
                    if now - last_cmd >= 0.05:
                        x, y, yaw = entity_xy_yaw(msg["payload"])
                        if now - race_stuck_t0 >= 0.5:
                            moved = math.hypot(x - race_last_xy[0], y - race_last_xy[1])
                            if moved < 0.7:
                                race_stuck_n += 1
                            else:
                                race_stuck_n = max(0, race_stuck_n - 1)
                            race_last_xy = (x, y)
                            race_stuck_t0 = now
                        while race_wp_i < len(race_wps) - 1:
                            tx, ty = race_wps[race_wp_i]
                            if math.hypot(tx - x, ty - y) < 8.0:
                                race_wp_i += 1
                            else:
                                break
                        tgt = race_wps[min(race_wp_i, len(race_wps) - 1)]
                        vx, vy, yr = race_chase_cmd(
                            x, y, yaw, tgt, speed=0.65, stuck=race_stuck_n >= 3
                        )
                        await _send_vel(ws, session_id, vx, vy, yr)
                        last_cmd = now

        if expect_objective:
            if not saw_objective:
                print("FAIL: expected objective_complete", file=sys.stderr)
                return 1
            print("smoke OK (objective)")
            return 0

        if not saw_take or not saw_state:
            print("FAIL: missing take_control event or state", file=sys.stderr)
            return 1
        if not saw_joints:
            print("FAIL: expected joints slide_x/slide_y/yaw_z on state", file=sys.stderr)
            return 1
        if not saw_wheels:
            print(
                "FAIL: expected F6 wheel joints left_wheel_joint/right_wheel_joint",
                file=sys.stderr,
            )
            return 1
        # demo_city spawn may be at negative x; require forward progress, not absolute x.
        if first_x is None or last_x is None or (last_x - first_x) < 0.4:
            print(
                "FAIL: expected motion in +x from vx=1",
                f"first={first_x} last={last_x}",
                file=sys.stderr,
            )
            return 1
        print("smoke OK")
        return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:8765")
    parser.add_argument("--seconds", type=float, default=1.5)
    parser.add_argument("--level-id", default="demo_workshop")
    parser.add_argument(
        "--expect-objective",
        action="store_true",
        help="Drive until objective_complete (demo_city / demo_race Manhattan)",
    )
    parser.add_argument(
        "--yaw-rate",
        type=float,
        default=None,
        help="Override yaw_rate (default 0.2; ignored for city/race --expect-objective)",
    )
    args = parser.parse_args()
    yaw = args.yaw_rate
    if yaw is None:
        yaw = 0.0 if args.expect_objective else 0.2
    seconds = args.seconds
    if args.expect_objective and args.level_id == "demo_city" and seconds < 120:
        seconds = 140.0
    if args.expect_objective and args.level_id == "demo_race" and seconds < 100:
        # Contact-wheel lap ~2 min offline; allow wall-time slack for 6-mech room.
        seconds = 240.0
    raise SystemExit(
        asyncio.run(
            smoke(
                args.url,
                seconds,
                level_id=args.level_id,
                expect_objective=args.expect_objective,
                yaw_rate=yaw,
            )
        )
    )


if __name__ == "__main__":
    main()
