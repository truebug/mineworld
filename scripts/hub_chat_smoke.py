#!/usr/bin/env python3
"""Smoke: two Hub clients; A chats → B receives event_type=chat."""
from __future__ import annotations

import asyncio
import json
import sys

try:
    import websockets
except ImportError:
    print("FAIL: websockets missing", file=sys.stderr)
    sys.exit(2)


async def _join(ws, sid: str, nick: str) -> None:
    """Join demo_hub public room with a display nickname."""
    await ws.send(
        json.dumps(
            {
                "type": "join",
                "session_id": sid,
                "payload": {
                    "level_id": "demo_hub",
                    "player_name": nick,
                    "room_id": "hub",
                    "extensions": {
                        "mw": {
                            "profile": {
                                "id": f"smoke-{nick}",
                                "nickname": nick,
                                "accent": "#4aa3ff",
                                "skin": "e",
                            }
                        }
                    },
                },
            }
        )
    )


async def _wait_type(ws, want: str, timeout: float = 8.0) -> dict:
    """Recv until message type matches."""
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        left = deadline - asyncio.get_event_loop().time()
        if left <= 0:
            raise TimeoutError(want)
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=left))
        if msg.get("type") == want:
            return msg


async def main() -> int:
    """Two sockets on hub; chat fan-out."""
    url = "ws://127.0.0.1:8765"
    async with websockets.connect(url, max_size=8 * 1024 * 1024) as a, websockets.connect(
        url, max_size=8 * 1024 * 1024
    ) as b:
        ha = await _wait_type(a, "hello")
        hb = await _wait_type(b, "hello")
        sa, sb = ha["session_id"], hb["session_id"]
        await _join(a, sa, "Alice")
        await _join(b, sb, "Bob")
        await _wait_type(a, "scene")
        await _wait_type(b, "scene")
        # Drain until controlled (optional take_control event).
        await asyncio.sleep(0.3)
        await a.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sa,
                    "payload": {"action": "chat", "text": "plaza-hi"},
                }
            )
        )
        got = None
        deadline = asyncio.get_event_loop().time() + 5.0
        while asyncio.get_event_loop().time() < deadline:
            msg = json.loads(
                await asyncio.wait_for(
                    b.recv(), timeout=max(0.1, deadline - asyncio.get_event_loop().time())
                )
            )
            if msg.get("type") != "event":
                continue
            pl = msg.get("payload") or {}
            if pl.get("event_type") == "chat":
                got = pl
                break
        if got is None:
            print("FAIL: no chat event on B")
            return 1
        detail = got.get("detail") or {}
        if detail.get("text") != "plaza-hi":
            print("FAIL: bad text", detail)
            return 1
        if detail.get("from") != "Alice":
            print("FAIL: bad from", detail)
            return 1
        print("hub chat smoke OK")
        return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
