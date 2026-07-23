"""B2 duel state-machine smoke: settle → pending → re-arm → next round.

In-process: fabricates Room + Sessions (no WS) and drives
EchoGateway._evaluate_race_duel with synthetic objective events.

Run: .venv/bin/python scripts/duel_smoke.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gateway"))

import echo_server as gw  # noqa: E402


def make_session(sid: str, eid: str, name: str) -> gw.Session:
    s = gw.Session(session_id=sid, ws=None, contract={"level_id": "demo_race"})  # type: ignore[arg-type]
    s.joined = True
    s.closed = False
    s.player_name = name
    s.controlled_entity_id = eid
    return s


def finish_event() -> dict:
    return {"event_type": "objective_complete", "objective_id": "obj_race_finish", "detail": {}}


def main() -> int:
    gateway = gw.EchoGateway(contract={"level_id": "demo_race"})
    room = gw.Room(room_id="r1", contract={"level_id": "demo_race"})
    room.tick = 100

    a = make_session("sa", "mech_player", "Alice")
    b = make_session("sb", "mech_player_b", "Bob")
    room.members = {"sa": a, "sb": b}
    room.mechs = {
        "mech_player": gw.MechState(entity_id="mech_player"),
        "mech_player_b": gw.MechState(entity_id="mech_player_b"),
    }
    a.room = room
    b.room = room

    # 1) first finisher with 2 players → duel settles, winner=Alice
    evs = gateway._evaluate_race_duel(a, room, [finish_event()])
    assert len(evs) == 1, f"expected 1 duel event, got {evs}"
    ev = evs[0]
    assert ev["event_type"] == "duel_result"
    assert ev["detail"]["winner_entity_id"] == "mech_player"
    assert ev["detail"]["winner_name"] == "Alice"
    assert ev["detail"]["round"] == 1
    assert sorted(ev["detail"]["participants"]) == ["mech_player", "mech_player_b"]
    assert room.duel_settled is True
    assert room.duel_pending == {"mech_player_b"}
    assert len(b.pending_events) == 1, "loser must get the event next tick"
    assert b.pending_events[0]["event_type"] == "duel_result"

    # 2) Bob finishes → no new event, round re-arms
    room.tick = 200
    evs2 = gateway._evaluate_race_duel(b, room, [finish_event()])
    assert evs2 == [], f"re-arm tick must not emit, got {evs2}"
    assert room.duel_settled is False, "round should re-arm after all pending finish"
    assert room.duel_armed_tick == 200

    # 3) next finish → round 2, winner=Bob this time? (Alice finishes first again)
    room.tick = 260
    evs3 = gateway._evaluate_race_duel(a, room, [finish_event()])
    assert len(evs3) == 1 and evs3[0]["detail"]["round"] == 2
    assert evs3[0]["detail"]["win_time_s"] == round((260 - 200) * gw.DT, 2)

    # 4) solo guard: Bob leaves → Alice finish must not settle a duel
    room.members.pop("sb")
    room.duel_settled = False
    room.duel_pending = {"mech_player_b"}
    evs4 = gateway._evaluate_race_duel(a, room, [finish_event()])
    assert evs4 == [], f"solo room must not settle duel, got {evs4}"
    assert room.duel_settled is False

    # 5) non-race level ignored
    room2 = gw.Room(room_id="r2", contract={"level_id": "demo_hub"})
    room2.members = {"sa": a}
    a.room = room2
    evs5 = gateway._evaluate_race_duel(a, room2, [finish_event()])
    assert evs5 == []

    print("duel smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
