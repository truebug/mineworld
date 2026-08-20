"""P0-1 smoke: disconnect with seat -> grace holds -> rejoin same profile adopts seat."""
import asyncio, json, sys
import websockets

URI = "ws://127.0.0.1:8765"
LEVEL, ROOM = "demo_chessroom", "grace_smoke"


async def recv_until(ws, pred, timeout=8.0):
    import time
    end = time.monotonic() + timeout
    while True:
        rem = end - time.monotonic()
        if rem <= 0:
            raise TimeoutError("recv timeout")
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=rem))
        if pred(msg):
            return msg


def table_ev(m, tid="table_1"):
    p = m.get("payload") or {}
    return (
        m.get("type") == "event"
        and p.get("event_type") == "chess_table_update"
        and (p.get("detail") or {}).get("table_id") == tid
    )


async def join_sit(profile_id):
    ws = await websockets.connect(URI)
    hello = await recv_until(ws, lambda m: m.get("type") == "hello")
    sid = hello["session_id"]
    await ws.send(json.dumps({
        "type": "join", "session_id": sid,
        "payload": {
            "level_id": LEVEL, "room_id": ROOM, "player_name": "Grace",
            "extensions": {"mw": {"profile": {"id": profile_id, "nickname": "Grace"}}},
        },
    }))
    await recv_until(ws, lambda m: m.get("type") == "scene")
    ev = await recv_until(ws, table_ev)
    await ws.send(json.dumps({
        "type": "cmd", "session_id": sid,
        "payload": {"action": "chess_sit", "table_id": "table_1"},
    }))
    ev = await recv_until(ws, table_ev)
    return ws, sid, ev["payload"]["detail"]


async def main():
    pid = "grace-player-1"
    ws1, sid1, det = await join_sit(pid)
    assert det.get("black_sid") == sid1, det
    # Hard disconnect (no bye) — seat should be held during grace.
    await ws1.close()
    ws2, sid2, det2 = await join_sit(pid)
    assert sid2 != sid1
    assert det2.get("black_sid") == sid2, ("seat not adopted", det2)
    # Guest rejoin (different profile) must NOT adopt: seat stays with sid2.
    ws3, sid3, det3 = await join_sit("grace-player-2")
    assert det3.get("black_sid") == sid2, det3
    await ws2.close(); await ws3.close()
    print("grace smoke OK")


asyncio.run(main())
