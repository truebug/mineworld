#!/usr/bin/env python3
"""Smoke: two clients join demo_hub room=hub and see each other in state."""

from __future__ import annotations

import asyncio
import json
import sys

import websockets


async def _client(
    url: str,
    name: str,
    ready: asyncio.Event,
    release: asyncio.Event,
) -> dict:
    """Join hub, signal ready, wait for release, return occupied snapshot."""
    async with websockets.connect(url) as ws:
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
                        "player_name": name,
                        "room_id": "hub",
                        "extensions": {
                            "mw": {
                                "profile": {
                                    "id": f"smoke-{name}",
                                    "nickname": name,
                                    "accent": "#ff8844",
                                }
                            }
                        },
                    },
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene
        eid = scene["payload"]["extensions"]["mw"]["controlled_entity_id"]
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": eid},
                }
            )
        )
        ready.set()
        await release.wait()
        deadline = asyncio.get_event_loop().time() + 1.5
        last_entities: dict = {}
        while asyncio.get_event_loop().time() < deadline:
            raw = await asyncio.wait_for(ws.recv(), timeout=5)
            msg = json.loads(raw)
            if msg.get("type") != "state":
                continue
            for ent in msg["payload"].get("entities") or []:
                last_entities[ent["entity_id"]] = ent
            occ = [
                e
                for e in last_entities.values()
                if (e.get("extensions") or {}).get("mw", {}).get("occupied")
            ]
            if len(occ) >= 2:
                break
        return {"entity_id": eid, "entities": last_entities, "name": name}


async def main() -> int:
    url = sys.argv[1] if len(sys.argv) > 1 else "ws://127.0.0.1:8765"
    ready_a = asyncio.Event()
    ready_b = asyncio.Event()
    release = asyncio.Event()
    a_task = asyncio.create_task(_client(url, "Alpha", ready_a, release))
    b_task = asyncio.create_task(_client(url, "Bravo", ready_b, release))
    await asyncio.wait_for(ready_a.wait(), timeout=5)
    await asyncio.wait_for(ready_b.wait(), timeout=5)
    release.set()
    a, b = await asyncio.gather(a_task, b_task)
    occ_a = [
        e
        for e in a["entities"].values()
        if (e.get("extensions") or {}).get("mw", {}).get("occupied")
    ]
    occ_b = [
        e
        for e in b["entities"].values()
        if (e.get("extensions") or {}).get("mw", {}).get("occupied")
    ]
    names_a = {(e.get("extensions") or {}).get("mw", {}).get("display_name") for e in occ_a}
    names_b = {(e.get("extensions") or {}).get("mw", {}).get("display_name") for e in occ_b}
    print("hub smoke A occupied", len(occ_a), names_a)
    print("hub smoke B occupied", len(occ_b), names_b)
    if len(occ_a) < 2 or len(occ_b) < 2:
        print("FAIL: expected 2 occupied avatars each")
        return 1
    if "Alpha" not in names_a or "Bravo" not in names_a:
        print("FAIL: A missing names", names_a)
        return 1
    if "Alpha" not in names_b or "Bravo" not in names_b:
        print("FAIL: B missing names", names_b)
        return 1
    print("hub smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
