"""Smoke-test MineWorld POC-A gateway: hello → join → take_control → velocity → state."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys

import websockets


async def smoke(url: str, seconds: float) -> int:
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
                    "payload": {"level_id": "tutorial_01", "player_name": "smoke"},
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
                        "yaw_rate": 0.2,
                    },
                }
            )
        )

        saw_event = False
        saw_state = False
        last_x = None
        deadline = asyncio.get_event_loop().time() + seconds
        while asyncio.get_event_loop().time() < deadline:
            raw = await asyncio.wait_for(ws.recv(), timeout=5)
            msg = json.loads(raw)
            if msg.get("type") == "event":
                saw_event = True
                print("event", msg["payload"].get("event_type"))
            elif msg.get("type") == "state":
                saw_state = True
                ent = msg["payload"]["entities"][0]
                last_x = ent["base_pose"]["x"]
                print(
                    f"state tick={msg['tick']} x={ent['base_pose']['x']:.3f} "
                    f"y={ent['base_pose']['y']:.3f} yaw={ent['base_pose']['yaw']:.3f}"
                )

        if not saw_event or not saw_state:
            print("FAIL: missing event or state", file=sys.stderr)
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
    args = parser.parse_args()
    raise SystemExit(asyncio.run(smoke(args.url, args.seconds)))


if __name__ == "__main__":
    main()
