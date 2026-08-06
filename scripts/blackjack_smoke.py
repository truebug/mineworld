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
        assert d.get("vs_ai") is False, "blackjack is always vs shared dealer"
        assert len(d.get("player_cards")) == 2, d
        if d.get("phase") == "playing":
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

        # redeal flow: sit → finished (stand early) → reset → playing again
        await ws.send(json.dumps({
            "type": "cmd", "session_id": sid,
            "payload": {"action": "chess_sit", "table_id": "table_2"},
        }))
        upd = await _recv_until(
            ws,
            lambda m: _is_table(m, "table_2")
            and (m["payload"]["detail"].get("black_sid") == sid),
        )
        d = upd["payload"]["detail"]
        assert d.get("status") in ("playing", "finished"), (
            "status must follow phase after sit, got %s" % d.get("status")
        )
        # force a quick finish (stand immediately if playing)
        if d.get("phase") == "playing":
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {"action": "card_stand", "table_id": "table_2"},
            }))
            upd = await _recv_until(
                ws,
                lambda m: _is_table(m, "table_2")
                and (m["payload"]["detail"].get("phase") == "finished"),
            )
            d = upd["payload"]["detail"]
        assert d.get("status") == "finished"
        # reset → redeal
        await ws.send(json.dumps({
            "type": "cmd", "session_id": sid,
            "payload": {"action": "chess_reset", "table_id": "table_2"},
        }))
        upd = await _recv_until(
            ws,
            lambda m: _is_table(m, "table_2")
            and (m["payload"]["detail"].get("phase") in ("playing", "finished")),
        )
        d = upd["payload"]["detail"]
        assert d.get("status") in ("playing", "finished"), (
            "status must follow phase after reset, got %s" % d.get("status")
        )
        assert len(d.get("player_cards", [])) == 2, "redeal must give 2 player cards"
        print(f"redeal ok phase={d['phase']} status={d['status']}")

        # --- two-player multi-hand: second client sits white, shared dealer ---
        async with websockets.connect(URL) as ws2:
            hello2 = await _recv_until(ws2, lambda m: m.get("type") == "hello")
            sid2 = str(hello2.get("session_id") or "")
            assert sid2 and sid2 != sid
            await ws2.send(json.dumps({
                "type": "join",
                "session_id": sid2,
                "payload": {"level_id": "demo_chessroom", "player_name": "BJ Smoke 2"},
            }))
            await _recv_until(ws2, lambda m: m.get("type") == "scene")
            # player 1 leaves first so both start a fresh round together
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {"action": "chess_leave", "table_id": "table_2"},
            }))
            await asyncio.sleep(0.3)
            await ws.send(json.dumps({
                "type": "cmd", "session_id": sid,
                "payload": {"action": "chess_sit", "table_id": "table_2"},
            }))
            await _recv_until(
                ws,
                lambda m: _is_table(m, "table_2")
                and (m["payload"]["detail"].get("black_sid") == sid),
            )
            await ws2.send(json.dumps({
                "type": "cmd", "session_id": sid2,
                "payload": {"action": "chess_sit", "table_id": "table_2"},
            }))
            upd = await _recv_until(
                ws2,
                lambda m: _is_table(m, "table_2")
                and (m["payload"]["detail"].get("white_sid") == sid2),
            )
            d = upd["payload"]["detail"]
            assert d.get("vs_ai") is False, "two humans must not be vs_ai"
            # p2 joined mid-round → watches; finish round, then reset deals both.
            if d.get("phase") == "playing":
                await ws.send(json.dumps({
                    "type": "cmd", "session_id": sid,
                    "payload": {"action": "card_stand", "table_id": "table_2"},
                }))
                upd = await _recv_until(
                    ws,
                    lambda m: _is_table(m, "table_2")
                    and (m["payload"]["detail"].get("phase") == "finished"),
                )
            await ws2.send(json.dumps({
                "type": "cmd", "session_id": sid2,
                "payload": {"action": "chess_reset", "table_id": "table_2"},
            }))
            upd = await _recv_until(
                ws2,
                lambda m: _is_table(m, "table_2")
                and len((m["payload"]["detail"].get("hands") or {})) == 2,
            )
            d = upd["payload"]["detail"]
            hands = d.get("hands") or {}
            assert set(hands.keys()) == {sid, sid2}, hands.keys()
            assert len(hands[sid]) == 2 and len(hands[sid2]) == 2, hands
            assert d.get("players") == [sid, sid2], d.get("players")
            print(f"two-player dealt p1={hands[sid]} p2={hands[sid2]} active={d.get('active_sid')}")

            # out-of-turn hit must be rejected
            active = str(d.get("active_sid") or "")
            if active == sid:
                idle_ws, idle_sid, act_ws, act_sid = ws2, sid2, ws, sid
            else:
                idle_ws, idle_sid, act_ws, act_sid = ws, sid, ws2, sid2
            if d.get("phase") == "playing" and active:
                await idle_ws.send(json.dumps({
                    "type": "cmd", "session_id": idle_sid,
                    "payload": {"action": "card_hit", "table_id": "table_2"},
                }))
                rej = await _recv_until(
                    idle_ws,
                    lambda m: m.get("type") == "event"
                    and (m.get("payload") or {}).get("event_type") == "chess_reject",
                )
                assert rej["payload"]["detail"].get("code") == "BJ_NOT_YOUR_TURN", rej
                print("out-of-turn hit rejected ok")

            # both stand (active player first, then the other)
            for cur_ws, cur_sid in ((act_ws, act_sid), (idle_ws, idle_sid)):
                # skip if this hand already settled (natural blackjack)
                await cur_ws.send(json.dumps({
                    "type": "cmd", "session_id": cur_sid,
                    "payload": {"action": "card_stand", "table_id": "table_2"},
                }))
                try:
                    upd = await _recv_until(
                        cur_ws,
                        lambda m: _is_table(m, "table_2"),
                        timeout=3.0,
                    )
                    d = upd["payload"]["detail"]
                except (AssertionError, asyncio.TimeoutError):
                    # rejected (already blackjack) — keep going
                    pass
            upd = await _recv_until(
                ws2,
                lambda m: _is_table(m, "table_2")
                and (m["payload"]["detail"].get("phase") == "finished"),
            )
            d = upd["payload"]["detail"]
            results = d.get("results") or {}
            assert sid in results and sid2 in results, results
            for s, r in results.items():
                assert r in ("win", "lose", "push", "blackjack"), (s, r)
            assert "??" not in d.get("dealer_cards", []), "hole must reveal"
            assert d.get("active_sid", "x") == "", "no active player after settle"
            dv = d.get("dealer_value", 0)
            live = [s for s in (sid, sid2) if results[s] not in ("blackjack", "lose")]
            if live:
                assert dv >= 17 or dv > 21, f"dealer must stand >=17 or bust, got {dv}"
            print(f"two-player settled results={results} dealer={d['dealer_cards']}({dv})")

            # mid-round reset blocked: only between rounds
            await ws2.send(json.dumps({
                "type": "cmd", "session_id": sid2,
                "payload": {"action": "chess_reset", "table_id": "table_2"},
            }))
            upd = await _recv_until(
                ws2,
                lambda m: _is_table(m, "table_2")
                and (m["payload"]["detail"].get("phase") in ("playing", "finished")),
            )
            d = upd["payload"]["detail"]
            if d.get("phase") == "playing":
                # reset during play must be ignored (no new deal broadcast)
                await ws.send(json.dumps({
                    "type": "cmd", "session_id": sid,
                    "payload": {"action": "chess_reset", "table_id": "table_2"},
                }))
                await asyncio.sleep(0.4)
                # both stand out to finish, then reset works
                active = str(d.get("active_sid") or "")
                order = [(ws, sid), (ws2, sid2)]
                if active == sid2:
                    order.reverse()
                for cur_ws, cur_sid in order:
                    await cur_ws.send(json.dumps({
                        "type": "cmd", "session_id": cur_sid,
                        "payload": {"action": "card_stand", "table_id": "table_2"},
                    }))
                    await asyncio.sleep(0.2)
                upd = await _recv_until(
                    ws,
                    lambda m: _is_table(m, "table_2")
                    and (m["payload"]["detail"].get("phase") == "finished"),
                )
            # cleanup: both leave
            await ws2.send(json.dumps({
                "type": "cmd", "session_id": sid2,
                "payload": {"action": "chess_leave", "table_id": "table_2"},
            }))
            await asyncio.sleep(0.3)

    print("blackjack smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
