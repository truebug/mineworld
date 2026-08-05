"""HW-0 hw_fake smoke: SO-101 arm lab over WS (ADR-004).

Spins expectations: hello → join demo_arm_lab → scene → take_control →
joint_targets chase with rate limits + soft-limit clamp + unknown-joint
rejection.

Run: .venv/bin/python scripts/hw_fake_smoke.py
Requires: gateway running with `--physics hw_fake` on ws://127.0.0.1:8765.
"""

from __future__ import annotations

import asyncio
import json
import sys

import websockets

URL = "ws://127.0.0.1:8765"


async def _recv_type(ws, want: str, timeout: float = 8.0) -> dict:
    """Drain until a message of type `want` arrives (events/states interleave)."""
    while True:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if msg.get("type") == want:
            return msg
        if msg.get("type") == "error":
            raise AssertionError(f"gateway error while waiting for {want}: {msg}")


async def _recv_state_with(ws, entity_id: str, timeout: float = 8.0) -> dict:
    """Drain state frames until one carries `entity_id` (delta frames may not)."""
    while True:
        msg = await _recv_type(ws, "state", timeout=timeout)
        ent = next((e for e in msg["payload"]["entities"]
                    if e.get("entity_id") == entity_id), None)
        if ent is not None:
            return ent


async def main() -> int:
    async with websockets.connect(URL) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello.get("type") == "hello", hello
        features = hello["payload"].get("features") or []
        assert "fake_kinematics" in features or "hw_fake_kinematics" in features, features
        session_id = hello["session_id"]
        print("hello ok · features =", features)

        await ws.send(json.dumps({
            "type": "join",
            "session_id": session_id,
            "payload": {"level_id": "demo_arm_lab", "player_name": "hw_smoke"},
        }))
        scene = await _recv_type(ws, "scene")
        assert scene["payload"]["level_id"] == "demo_arm_lab", scene
        ents = scene["payload"]["entities"]
        arm = next(e for e in ents if e["entity_id"] == "arm_0")
        assert arm.get("controllable") is True, arm
        print("scene ok · entities =", [e["entity_id"] for e in ents])

        # First state frame: arm sits at HOME pose (enabled=False → no drift).
        state0 = await _recv_type(ws, "state")
        ent0 = next(e for e in state0["payload"]["entities"]
                    if e["entity_id"] == "arm_0")
        joints = ent0["joints"]
        assert set(joints) >= {"shoulder_pan", "shoulder_lift", "elbow_flex",
                               "wrist_flex", "wrist_roll", "gripper"}, joints
        assert abs(joints["shoulder_pan"] - 0.0) < 1e-6, joints  # home pose
        assert ent0["extensions"]["mw"]["hw_machine"] == "so101", ent0
        print("state ok · home joints =", {k: round(v, 3) for k, v in joints.items()})

        await ws.send(json.dumps({
            "type": "cmd",
            "session_id": session_id,
            "payload": {"action": "take_control", "entity_id": "arm_0"},
        }))

        # Unknown joint must be rejected (open-subset contract pin).
        await ws.send(json.dumps({
            "type": "cmd",
            "session_id": session_id,
            "payload": {"entity_id": "arm_0", "joint_targets": {"flux_capacitor": 1.0}},
        }))
        err = await _recv_type(ws, "error")
        assert err["payload"]["code"] == "UNKNOWN_JOINT", err
        print("unknown joint rejected ok")

        # Chase target within rate limit.
        await ws.send(json.dumps({
            "type": "cmd",
            "session_id": session_id,
            "payload": {"entity_id": "arm_0",
                        "joint_targets": {"shoulder_pan": 0.5, "gripper": 1.0}},
        }))
        await asyncio.sleep(1.5)
        ent = await _recv_state_with(ws, "arm_0")
        got = ent["joints"]
        assert abs(got["shoulder_pan"] - 0.5) < 0.05, got
        assert abs(got["gripper"] - 1.0) < 0.05, got
        assert ent["extensions"]["mw"]["hw_machine"] == "so101", ent
        assert ent["extensions"]["mw"]["hw_enabled"] is True, ent
        print("chase ok ·", {k: round(got[k], 3) for k in ("shoulder_pan", "gripper")})

        # Soft-limit clamp: shoulder_pan limit is ±1.92 rad.
        await ws.send(json.dumps({
            "type": "cmd",
            "session_id": session_id,
            "payload": {"entity_id": "arm_0", "joint_targets": {"shoulder_pan": 9.9}},
        }))
        await asyncio.sleep(3.0)
        ent = await _recv_state_with(ws, "arm_0")
        clamped = ent["joints"]["shoulder_pan"]
        assert clamped <= 1.92 + 1e-6, clamped
        print("soft-limit clamp ok · shoulder_pan =", round(clamped, 3))

    print("hw_fake smoke OK")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except (AssertionError, asyncio.TimeoutError, OSError) as exc:
        print(f"hw_fake smoke FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
