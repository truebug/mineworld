"""V3a: push prop_crate into trigger_bin on demo_workshop (MuJoCo only)."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys

import websockets


async def _send_vel(ws, session_id: str, vx: float, yaw_rate: float = 0.0) -> None:
    """Send a chassis velocity cmd."""
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


async def stow_crate(url: str, *, seconds: float) -> int:
    """Join demo_workshop, drive +x, require objective_complete for prop_crate."""
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
                    "payload": {"level_id": "demo_workshop", "player_name": "stow"},
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
        await _send_vel(ws, sid, 1.6, 0.0)

        saw_objective = False
        crate_x = None
        deadline = asyncio.get_event_loop().time() + seconds
        while asyncio.get_event_loop().time() < deadline:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            if msg.get("type") == "event":
                et = (msg.get("payload") or {}).get("event_type")
                print("event", et, (msg.get("payload") or {}).get("objective_id", ""))
                if et == "objective_complete":
                    saw_objective = True
                    break
            elif msg.get("type") == "state":
                for ent in msg["payload"]["entities"]:
                    if ent.get("entity_id") != "prop_crate":
                        continue
                    crate_x = float(ent["base_pose"]["x"])
                    print(f"prop_crate x={crate_x:.3f}")

        if not saw_objective:
            print(
                f"FAIL: expected objective_complete (last crate x={crate_x})",
                file=sys.stderr,
            )
            return 1
        print("stow-crate OK")
        return 0


def main() -> None:
    """CLI entry for workshop bin objective smoke."""
    parser = argparse.ArgumentParser(description="V3a workshop stow-crate smoke")
    parser.add_argument("--url", default="ws://127.0.0.1:8765")
    parser.add_argument("--seconds", type=float, default=28.0)
    args = parser.parse_args()
    raise SystemExit(asyncio.run(stow_crate(args.url, seconds=args.seconds)))


if __name__ == "__main__":
    main()
