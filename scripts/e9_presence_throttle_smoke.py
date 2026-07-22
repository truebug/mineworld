#!/usr/bin/env python3
"""E9 smoke: Hub presence_throttle pauses state flood (keepalive only)."""
from __future__ import annotations

import asyncio
import json
import sys
import time

try:
    import websockets
except ImportError:
    print("FAIL: websockets missing", file=sys.stderr)
    sys.exit(2)


async def main() -> int:
    """Join hub, pause presence, count state frames."""
    url = "ws://127.0.0.1:8765"
    async with websockets.connect(url, max_size=8 * 1024 * 1024) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello.get("type") == "hello", hello
        sid = hello["session_id"]
        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": sid,
                    "payload": {
                        "level_id": "demo_hub",
                        "room_id": "hub",
                        "player_name": "e9smoke",
                    },
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene
        entity_id = "avatar_0"
        for ent in scene.get("payload", {}).get("entities", []):
            eid = str(ent.get("entity_id", ""))
            if eid.startswith("avatar_"):
                entity_id = eid
                break
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": entity_id},
                }
            )
        )
        t0 = time.monotonic()
        full_n = 0
        while time.monotonic() - t0 < 0.55:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=0.2)
            except TimeoutError:
                continue
            if json.loads(raw).get("type") == "state":
                full_n += 1
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {
                        "action": "presence_throttle",
                        "level": "paused",
                        "entity_id": entity_id,
                    },
                }
            )
        )
        t1 = time.monotonic()
        paused_n = 0
        while time.monotonic() - t1 < 1.2:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=0.25)
            except TimeoutError:
                continue
            if json.loads(raw).get("type") == "state":
                paused_n += 1
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {
                        "action": "presence_throttle",
                        "level": "full",
                        "entity_id": entity_id,
                    },
                }
            )
        )
    print(f"e9 presence_throttle: full≈{full_n}/0.55s paused={paused_n}/1.2s")
    if full_n < 4:
        print("FAIL: expected several full-rate state frames", file=sys.stderr)
        return 1
    if paused_n > 4:
        print("FAIL: paused should downclock state heavily", file=sys.stderr)
        return 1
    print("e9 presence_throttle OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
