"""Smoke: joint_targets move arm joints under MuJoCo (V1b).

Requires Gateway with workshop contract + --physics mujoco.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time

import websockets

TARGETS = {
    "arm_yaw": 0.5,
    "arm_shoulder": 0.7,
    "arm_elbow": -1.0,
    "gripper": 0.04,
}


async def smoke(url: str, level_id: str, settle_s: float) -> int:
    """Join, take control, set joint_targets, assert joints approach setpoints."""
    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello.get("type") == "hello", hello
        session_id = hello["session_id"]

        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": session_id,
                    "payload": {"level_id": level_id, "player_name": "joint_smoke"},
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene

        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": session_id,
                    "payload": {"entity_id": "mech_player", "action": "take_control"},
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
                        "control_mode": "joint_targets",
                        "joint_targets": TARGETS,
                    },
                }
            )
        )

        # Bad name must error.
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": session_id,
                    "payload": {
                        "entity_id": "mech_player",
                        "control_mode": "joint_targets",
                        "joint_targets": {"not_a_joint": 1.0},
                    },
                }
            )
        )

        saw_error = False
        joints_ok = False
        deadline = time.monotonic() + settle_s + 2.0
        while time.monotonic() < deadline:
            raw = await asyncio.wait_for(ws.recv(), timeout=5)
            msg = json.loads(raw)
            if msg.get("type") == "error":
                code = (msg.get("payload") or {}).get("code")
                if code == "UNKNOWN_JOINT":
                    saw_error = True
                continue
            if msg.get("type") != "state":
                continue
            ents = (msg.get("payload") or {}).get("entities") or []
            mech = next((e for e in ents if e.get("entity_id") == "mech_player"), None)
            if not mech:
                continue
            joints = mech.get("joints") or {}
            if not all(k in joints for k in TARGETS):
                continue
            errs = {k: abs(float(joints[k]) - float(v)) for k, v in TARGETS.items()}
            if all(e < 0.15 for e in errs.values()):
                joints_ok = True
                print("joints near targets", {k: round(float(joints[k]), 3) for k in TARGETS})
                break

        if not saw_error:
            print("FAIL: expected UNKNOWN_JOINT error", file=sys.stderr)
            return 1
        if not joints_ok:
            print("FAIL: arm joints did not approach targets", file=sys.stderr)
            return 1
        print("joint_targets smoke OK")
        return 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:8765")
    parser.add_argument("--level-id", default="demo_workshop")
    parser.add_argument("--settle", type=float, default=1.5)
    args = parser.parse_args()
    raise SystemExit(asyncio.run(smoke(args.url, args.level_id, args.settle)))


if __name__ == "__main__":
    main()
