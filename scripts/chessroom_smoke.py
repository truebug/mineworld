"""Smoke: join demo_chessroom → sit → place → expect chess_table_update + AI reply."""
from __future__ import annotations

import asyncio
import json
import sys

import websockets

URI = "ws://127.0.0.1:8765"
LEVEL = "demo_chessroom"
ROOM = "chess-smoke"


async def _recv_until(ws, pred, timeout: float = 8.0):
    """Receive envelopes until pred(msg) or timeout."""
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            raise TimeoutError("recv timeout")
        raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        msg = json.loads(raw)
        if pred(msg):
            return msg


async def main() -> int:
    async with websockets.connect(URI) as ws:
        hello = await _recv_until(ws, lambda m: m.get("type") == "hello")
        sid = hello["session_id"]
        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": sid,
                    "payload": {
                        "level_id": LEVEL,
                        "room_id": ROOM,
                        "player_name": "ChessSmoke",
                    },
                }
            )
        )
        scene = await _recv_until(ws, lambda m: m.get("type") == "scene")
        eid = (
            ((scene.get("payload") or {}).get("extensions") or {})
            .get("mw", {})
            .get("controlled_entity_id")
        )
        assert eid, "no controlled_entity_id"
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": eid},
                }
            )
        )
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "chess_sit", "table_id": "table_1"},
                }
            )
        )
        sit_ev = await _recv_until(
            ws,
            lambda m: m.get("type") == "event"
            and (m.get("payload") or {}).get("event_type") == "chess_table_update"
            and ((m.get("payload") or {}).get("detail") or {}).get("status")
            == "playing",
        )
        detail = sit_ev["payload"]["detail"]
        assert detail.get("vs_ai") is True
        assert detail.get("black_sid") == sid
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {
                        "action": "chess_place",
                        "table_id": "table_1",
                        "x": 7,
                        "y": 7,
                    },
                }
            )
        )
        place_ev = await _recv_until(
            ws,
            lambda m: m.get("type") == "event"
            and (m.get("payload") or {}).get("event_type") == "chess_table_update"
            and sum(
                1
                for c in ((m.get("payload") or {}).get("detail") or {}).get("cells")
                or []
                if c
            )
            >= 2,
        )
        cells = place_ev["payload"]["detail"]["cells"]
        assert cells[7 * 15 + 7] == 1, "black center stone missing"
        white = sum(1 for c in cells if c == 2)
        assert white >= 1, "AI white reply missing"
        # Checkers table: sit + one move
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "chess_leave", "table_id": "table_1"},
                }
            )
        )
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "chess_sit", "table_id": "table_3"},
                }
            )
        )
        ck = await _recv_until(
            ws,
            lambda m: m.get("type") == "event"
            and (m.get("payload") or {}).get("event_type") == "chess_table_update"
            and ((m.get("payload") or {}).get("detail") or {}).get("game") == "checkers"
            and ((m.get("payload") or {}).get("detail") or {}).get("status")
            == "playing",
        )
        assert ck["payload"]["detail"].get("board_size") == 8
        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {
                        "action": "chess_move",
                        "table_id": "table_3",
                        "fx": 0,
                        "fy": 3,
                        "tx": 0,
                        "ty": 4,
                    },
                }
            )
        )
        await _recv_until(
            ws,
            lambda m: m.get("type") == "event"
            and (m.get("payload") or {}).get("event_type") == "chess_table_update"
            and ((m.get("payload") or {}).get("detail") or {}).get("table_id")
            == "table_3"
            and len(
                ((m.get("payload") or {}).get("detail") or {}).get("cells") or []
            )
            >= 64
            and (
                ((m.get("payload") or {}).get("detail") or {}).get("cells") or [0]
            )[4 * 8 + 0]
            == 1,
        )
        print("chessroom smoke OK")
        return 0


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except Exception as exc:  # noqa: BLE001
        print(f"chessroom smoke FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
