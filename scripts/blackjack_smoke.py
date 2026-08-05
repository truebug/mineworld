"""Blackjack smoke: join chessroom → sit table_2 → hit/stand → settled result.

Run: .venv/bin/python gateway/echo_server.py & then
     .venv/bin/python scripts/blackjack_smoke.py
"""

from __future__ import annotations

import asyncio
import json
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".venv" / "lib"))

import websockets  # noqa: E402

URL = "ws://127.0.0.1:8765"


async def _recv_until(ws, pred, timeout: float = 8.0):
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if pred(msg):
            return msg
    raise AssertionError("timeout waiting for predicate")


def _is_table(msg, table_id: str) -> bool:
    if msg.get("type") != "event":
        return False
    p = msg.get("payload") or {}
    return p.get("event_type") == "chess_table_update" and (p.get("detail") or {}).get("table_id") == table_id


async def main() -> int:
    async with websockets.connect(URL) as ws:
        hello = await _recv_until(ws, lambda m: m.get("type") == "hello")
        sid = str(hello.get("session_id") or "")
        assert sid, "hello must carry gateway session_id"
        await ws.send(json.dumps({
            "type": "join",
            "session_id": sid,
            "payload": {"level_id": "demo_chessroom", "player_name": "BJ Smoke"},
        }))
        await _recv_until(ws, lambda m: m.get("type") == "scene")

        # sit → deal
        await ws.send(json.dumps({
            "type": "cmd", "session_id": sid,
            "payload": {"action": "chess_sit", "table_id": "table_2"},
        }))
        # join may broadcast initial (empty) table state first — wait for our seat.
        upd = await _recv_until(
            ws,
            lambda m: _is_table(m, "table_2")
            and (m["payload"]["detail"].get("black_sid") == sid),
        )
        d = upd["payload"]["detail"]
        assert d.get("game") == "blackjack", d.get("game")
        assert d.get("black_sid") == sid
        assert d.get("vs_ai") is True
        assert len(d.get("player_cards")) == 2, d
        assert d.get("dealer_cards", ["?", "?"])[1] == "??", "hole card must be hidden"
        assert d.get("phase") in ("playing", "finished"), d
        print(f"sit ok phase={d['phase']} player={d['player_cards']}({d['player_value']}) dealer={d['dealer_cards']}")

        if d["phase"] == "finished":
            # natural blackjack dealt; reset for an action round
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {"action": "chess_reset", "table_id": "table_2"},
            }))
            upd = await _recv_until(ws, lambda m: _is_table(m, "table_2") and (m["payload"]["detail"].get("phase") == "playing"))
            d = upd["payload"]["detail"]

        # hit until >= 12 then stand
        while d.get("phase") == "playing" and d.get("player_value", 0) < 12:
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {"action": "card_hit", "table_id": "table_2"},
            }))
            upd = await _recv_until(ws, lambda m: _is_table(m, "table_2"))
            d = upd["payload"]["detail"]
            print(f"hit → player={d['player_cards']}({d['player_value']}) phase={d['phase']}")

        if d.get("phase") == "playing":
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {"action": "card_stand", "table_id": "table_2"},
            }))
            upd = await _recv_until(ws, lambda m: _is_table(m, "table_2") and (m["payload"]["detail"].get("phase") == "finished"))
            d = upd["payload"]["detail"]

        assert d.get("phase") == "finished", d
        assert d.get("status") == "finished", d
        assert d.get("result") in ("win", "lose", "push", "blackjack"), d
        assert "??" not in d.get("dealer_cards", []), "hole card must reveal at settle"
        assert len(d.get("dealer_cards", [])) >= 2
        dv = d.get("dealer_value", 0)
        assert dv >= 17 or dv > 21, f"dealer must stand >=17 or bust, got {dv}"
        print(f"settled result={d['result']} dealer={d['dealer_cards']}({dv}) player={d['player_value']}")

        # leave clears seat
        await ws.send(json.dumps({
            "type": "cmd", "session_id": sid,
            "payload": {"action": "chess_leave", "table_id": "table_2"},
        }))
        await asyncio.sleep(0.3)

    print("blackjack smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
