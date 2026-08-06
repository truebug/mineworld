"""五对 (WuDui) smoke: two players sit table_6 → discard/eat/pass → settle.

Run: .venv/bin/python gateway/echo_server.py & then
     .venv/bin/python scripts/wudui_smoke.py
"""

from __future__ import annotations

import asyncio
import json
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gateway"))

import websockets  # noqa: E402

URL = "ws://127.0.0.1:8765"
TID = "table_6"


async def _recv_until(ws, pred, timeout: float = 8.0):
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if pred(msg):
            return msg
    raise AssertionError("timeout waiting for predicate")


def _table(msg, tid: str = TID) -> dict:
    return (msg.get("payload") or {}).get("detail", {})


def _is_table(msg, tid: str = TID) -> bool:
    p = msg.get("payload") or {}
    return (msg.get("type") == "event"
            and p.get("event_type") == "chess_table_update"
            and (p.get("detail") or {}).get("table_id") == tid)


async def main() -> int:
    a = await websockets.connect(URL)
    b = await websockets.connect(URL)
    sa = json.loads(await asyncio.wait_for(a.recv(), 5))["session_id"]
    sb = json.loads(await asyncio.wait_for(b.recv(), 5))["session_id"]
    await a.send(json.dumps({"type": "join", "session_id": sa,
                             "payload": {"level_id": "demo_chessroom", "player_name": "p1"}}))
    await b.send(json.dumps({"type": "join", "session_id": sb,
                             "payload": {"level_id": "demo_chessroom", "player_name": "p2"}}))
    await _recv_until(a, lambda m: m.get("type") == "scene")
    await _recv_until(b, lambda m: m.get("type") == "scene")

    # p1 sits black (first), p2 sits red (second) → deal starts.
    await a.send(json.dumps({"type": "cmd", "session_id": sa,
                             "payload": {"action": "chess_sit", "table_id": TID}}))
    msg = await _recv_until(a, lambda m: _is_table(m) and _table(m).get("black_sid") == sa)
    assert _table(msg).get("game") == "wudui"
    assert _table(msg).get("phase") == "idle"  # waiting for second
    print("p1 seated black · waiting for second")

    await b.send(json.dumps({"type": "cmd", "session_id": sb,
                             "payload": {"action": "chess_sit", "table_id": TID}}))
    msg = await _recv_until(b, lambda m: _is_table(m) and _table(m).get("phase") == "playing")
    t = _table(msg)
    assert t.get("phase") == "playing", t
    assert len(t.get("black_cards", [])) == 11, t
    assert len(t.get("red_cards", [])) == 10, t
    assert t.get("turn") == "black", t
    print("dealt ok · black=11 red=10 · turn=black · pairs=%s/%s" % (
        t.get("black_pairs"), t.get("red_pairs")))

    # p1 (black) discards an unmatched card.
    def pick_unmatched(cards: list):
        from collections import Counter
        cnt = Counter(c[:-1] if c != "JOKER" else "JOKER" for c in cards)
        return next(c for c in cards if cnt[(c[:-1] if c != "JOKER" else "JOKER")] % 2 == 1)

    black = list(t.get("black_cards", []))
    disc = pick_unmatched(black)
    await a.send(json.dumps({"type": "cmd", "session_id": sa,
                             "payload": {"action": "card_discard", "table_id": TID, "card": disc}}))
    msg = await _recv_until(a, lambda m: _is_table(m) and _table(m).get("turn") == "red" and _table(m).get("last_action") == "discard")
    t = _table(msg)
    assert t.get("turn") == "red", t
    assert t.get("last_action") == "discard", t
    assert disc not in t.get("black_cards", []), t
    print("black discard ok · top discard =", t.get("discard_pile"))

    # p2 (red) pass + discard.
    red = list(t.get("red_cards", []))
    rdisc = pick_unmatched(red)
    await b.send(json.dumps({"type": "cmd", "session_id": sb,
                             "payload": {"action": "card_pass", "table_id": TID, "discard": rdisc}}))
    msg = await _recv_until(b, lambda m: _is_table(m) and _table(m).get("turn") == "black" and _table(m).get("last_action") == "pass")
    t = _table(msg)
    assert t.get("turn") == "black", t
    assert t.get("last_action") == "pass", t
    assert len(t.get("red_cards", [])) == 10, t  # drew then discarded
    print("red pass+draw+discard ok")

    # Wrong turn guard: p2 tries discard while black's turn.
    await b.send(json.dumps({"type": "cmd", "session_id": sb,
                             "payload": {"action": "card_discard", "table_id": TID, "card": "AS"}}))
    msg = await _recv_until(b, lambda m: (m.get("payload") or {}).get("event_type") == "chess_reject")
    assert "WUDUI" in str(_table(msg).get("code", "")), msg
    print("wrong-turn reject ok ·", _table(msg).get("code"))

    # Resign settles.
    await b.send(json.dumps({"type": "cmd", "session_id": sb,
                             "payload": {"action": "chess_resign", "table_id": TID}}))
    msg = await _recv_until(b, lambda m: _is_table(m) and _table(m).get("status") == "finished")
    t = _table(msg)
    assert t.get("status") == "finished" and t.get("winner") == "black", t
    print("resign ok · winner=black reason=%s" % t.get("reason"))

    # Redo: reset → redeal.
    await a.send(json.dumps({"type": "cmd", "session_id": sa,
                             "payload": {"action": "chess_reset", "table_id": TID}}))
    msg = await _recv_until(a, lambda m: _is_table(m) and _table(m).get("last_action") == "deal" and _table(m).get("phase") == "playing")
    t = _table(msg)
    assert t.get("phase") == "playing" and t.get("last_action") == "deal", t
    print("redeal ok · phase=playing")

    await a.close()
    await b.close()
    print("wudui smoke OK")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except (AssertionError, asyncio.TimeoutError, OSError) as exc:
        print(f"wudui smoke FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
