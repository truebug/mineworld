#!/usr/bin/env python3
"""Smoke: Hub set_hub_floor appears on peer state extensions.mw.hub_floor."""

from __future__ import annotations

import asyncio
import json
import sys

import websockets


async def main(url: str) -> int:
    async with websockets.connect(url) as a, websockets.connect(url) as b:
        ha = json.loads(await asyncio.wait_for(a.recv(), timeout=5))
        hb = json.loads(await asyncio.wait_for(b.recv(), timeout=5))
        sa, sb = ha["session_id"], hb["session_id"]

        async def join(ws, sid: str, name: str) -> str:
            await ws.send(
                json.dumps(
                    {
                        "type": "join",
                        "session_id": sid,
                        "payload": {
                            "level_id": "demo_hub",
                            "player_name": name,
                            "room_id": "hub",
                            "extensions": {
                                "mw": {
                                    "profile": {
                                        "id": f"floor-{name}",
                                        "nickname": name,
                                        "accent": "#4aa3ff",
                                    }
                                }
                            },
                        },
                    }
                )
            )
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
                if msg.get("type") == "scene":
                    return str(msg["payload"]["extensions"]["mw"]["controlled_entity_id"])

        ea = await join(a, sa, "FloorA")
        eb = await join(b, sb, "FloorB")
        await a.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sa,
                    "payload": {"action": "take_control", "entity_id": ea},
                }
            )
        )
        await b.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sb,
                    "payload": {"action": "take_control", "entity_id": eb},
                }
            )
        )
        await a.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sa,
                    "payload": {"action": "set_hub_floor", "floor": 2},
                }
            )
        )
        deadline = asyncio.get_event_loop().time() + 3.0
        saw = None
        while asyncio.get_event_loop().time() < deadline:
            msg = json.loads(await asyncio.wait_for(b.recv(), timeout=5))
            if msg.get("type") != "state":
                continue
            for ent in msg["payload"].get("entities") or []:
                if ent.get("entity_id") != ea:
                    continue
                mw = (ent.get("extensions") or {}).get("mw") or {}
                if int(mw.get("hub_floor", 1)) == 2:
                    saw = mw
                    break
            if saw is not None:
                break
        if saw is None:
            print("FAIL: peer never saw hub_floor=2 for", ea, file=sys.stderr)
            return 1
        print("hub_floor smoke OK", ea, saw.get("hub_floor"), "occupied", saw.get("occupied"))
        return 0


if __name__ == "__main__":
    u = sys.argv[1] if len(sys.argv) > 1 else "ws://127.0.0.1:8765"
    raise SystemExit(asyncio.run(main(u)))
