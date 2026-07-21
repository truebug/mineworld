"""T4.6 / D2: drive into prop_crate and assert it moves (MuJoCo only)."""

from __future__ import annotations

import asyncio
import json
import sys

import websockets


async def push_box(url: str = "ws://127.0.0.1:8765") -> int:
    """Join demo_city, drive +x, require prop_crate.x to increase."""
    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello.get("type") == "hello", hello
        if "mujoco" not in (hello.get("payload") or {}).get("features", []):
            print("FAIL: need --physics mujoco", file=sys.stderr)
            return 1
        sid = hello["session_id"]
        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": sid,
                    "payload": {
                        "level_id": "demo_city",
                        "player_name": "push",
                        "room_id": "push-box-smoke",
                    },
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene
        kinds = {e.get("entity_id"): e.get("kind") for e in scene["payload"]["entities"]}
        assert kinds.get("prop_crate") == "dynamic_prop", kinds

        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": "mech_player"},
                }
            )
        )
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {
                        "entity_id": "mech_player",
                        "control_mode": "velocity",
                        "vx": 1.5,
                        "vy": 0.0,
                        "yaw_rate": 0.0,
                    },
                }
            )
        )

        x0 = None
        x_last = None
        deadline = asyncio.get_event_loop().time() + 6.0
        while asyncio.get_event_loop().time() < deadline:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            if msg.get("type") != "state":
                continue
            for ent in msg["payload"]["entities"]:
                if ent.get("entity_id") != "prop_crate":
                    continue
                x = float(ent["base_pose"]["x"])
                if x0 is None:
                    x0 = x
                x_last = x
                print(f"prop_crate x={x:.3f} (Δ={x - x0:.3f})")
        if x0 is None or x_last is None:
            print("FAIL: never saw prop_crate in state", file=sys.stderr)
            return 1
        if x_last - x0 < 0.15:
            print(f"FAIL: expected push Δx>=0.15, got {x_last - x0:.3f}", file=sys.stderr)
            return 1
        print("push-box OK")
        return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(push_box()))
