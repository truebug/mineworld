"""Smoke-test MineWorld gateway: hello → join → take_control → velocity → state.

Optional --expect-objective: follow demo_city maze open-loop until objective_complete.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys

import websockets

# demo_city: straight E-W corridor spawn → finish (~51 m at vx=1).
DEMO_CITY_FINISH_SCRIPT: list[tuple[float, float, float]] = [
    (1.0, 0.0, 58.0),
]


async def _send_vel(ws, session_id: str, vx: float, yaw_rate: float) -> None:
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
                    "vy": 0.0,
                    "yaw_rate": yaw_rate,
                },
            }
        )
    )


async def _run_vel_script(
    ws, session_id: str, script: list[tuple[float, float, float]]
) -> None:
    """Open-loop velocity segments (vx, yaw_rate, duration_s)."""
    for vx, yaw_rate, dur in script:
        await _send_vel(ws, session_id, vx, yaw_rate)
        await asyncio.sleep(dur)
    await _send_vel(ws, session_id, 0.0, 0.0)


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

        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": session_id,
                    "payload": {"level_id": level_id, "player_name": "smoke"},
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

        script_task = None
        drive_yaw = 0.0 if level_id == "demo_city" else yaw_rate
        if expect_objective and level_id == "demo_city":
            print("note: demo_city corridor — open-loop +x to finish")
            script_task = asyncio.create_task(
                _run_vel_script(ws, session_id, DEMO_CITY_FINISH_SCRIPT)
            )
        elif expect_objective:
            await _send_vel(ws, session_id, 1.0, drive_yaw)
        else:
            await _send_vel(ws, session_id, 1.0, drive_yaw)

        saw_take = False
        saw_objective = False
        saw_state = False
        saw_joints = False
        saw_wheels = False
        first_x = None
        last_x = None
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
                if "left_wheel_joint" in joints and "right_wheel_joint" in joints:
                    saw_wheels = True
                print(
                    f"state tick={msg['tick']} x={ent['base_pose']['x']:.3f} "
                    f"y={ent['base_pose']['y']:.3f} yaw={ent['base_pose']['yaw']:.3f} "
                    f"joints={bool(joints)} wheels={saw_wheels}"
                )

        if script_task is not None and not script_task.done():
            script_task.cancel()
            try:
                await script_task
            except asyncio.CancelledError:
                pass

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
    parser.add_argument("--level-id", default="demo_city")
    parser.add_argument(
        "--expect-objective",
        action="store_true",
        help="Drive until objective_complete (demo_city: straight corridor ~58s)",
    )
    parser.add_argument(
        "--yaw-rate",
        type=float,
        default=None,
        help="Override yaw_rate (default 0.2; ignored for demo_city --expect-objective)",
    )
    args = parser.parse_args()
    yaw = args.yaw_rate
    if yaw is None:
        yaw = 0.0 if args.expect_objective else 0.2
    seconds = args.seconds
    if args.expect_objective and seconds < 18.0:
        seconds = 65.0 if args.level_id == "demo_city" else 18.0
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
