"""Smoke-test MineWorld gateway: hello → join → take_control → velocity → state.

Optional --expect-objective: drive straight until objective_complete (T3.1).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys

import websockets


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
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": session_id,
                    "payload": {
                        "entity_id": "mech_player",
                        "control_mode": "velocity",
                        "vx": 1.0,
                        "vy": 0.0,
                        "yaw_rate": yaw_rate,
                    },
                }
            )
        )

        saw_take = False
        saw_objective = False
        saw_state = False
        saw_joints = False
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
                joints = ent.get("joints") or {}
                if "slide_x" in joints and "slide_y" in joints and "yaw_z" in joints:
                    saw_joints = True
                print(
                    f"state tick={msg['tick']} x={ent['base_pose']['x']:.3f} "
                    f"y={ent['base_pose']['y']:.3f} yaw={ent['base_pose']['yaw']:.3f} "
                    f"joints={bool(joints)}"
                )

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
        if last_x is None or last_x <= 0.05:
            print("FAIL: expected motion in +x from vx=1", last_x, file=sys.stderr)
            return 1
        print("smoke OK")
        return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:8765")
    parser.add_argument("--seconds", type=float, default=1.5)
    parser.add_argument("--level-id", default="tutorial_01")
    parser.add_argument(
        "--expect-objective",
        action="store_true",
        help="Drive until objective_complete (use yaw_rate=0; needs ~10s on tutorial_01)",
    )
    parser.add_argument(
        "--yaw-rate",
        type=float,
        default=None,
        help="Override yaw_rate (default 0.2; 0.0 when --expect-objective)",
    )
    args = parser.parse_args()
    yaw = args.yaw_rate
    if yaw is None:
        yaw = 0.0 if args.expect_objective else 0.2
    seconds = args.seconds
    if args.expect_objective and seconds < 12.0:
        seconds = 12.0
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
