"""ADR-011: RoomPolicy — room_id / capacity / mode decisions, one place.

Behavior mirrors the legacy _handle_join branch chain exactly:
hub (mw.mode=hub, incl. chessroom) → contract max_members, default room "hub";
demo_city → shared "city" max 5; demo_race → "race" max 6 (duel explicit room 6,
else private solo, single chassis); named public rooms keep their caps; anything
else is a private solo room. Matchmaker is a stub (returns None).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

DEMO_ROOM_ID = "demo"
DEMO_ROOM_MAX = 2
CITY_ROOM_ID = "city"
CITY_ROOM_MAX = 5
RACE_ROOM_ID = "race"
RACE_ROOM_MAX = 6
RACE_MODES = ("solo", "duel", "shared_ffa")
HUB_ROOM_ID = "hub"
CHESS_ROOM_ID = "chess"

PUBLIC_ROOM_CAPS = {
    DEMO_ROOM_ID: DEMO_ROOM_MAX,
    CITY_ROOM_ID: CITY_ROOM_MAX,
    RACE_ROOM_ID: RACE_ROOM_MAX,
    CHESS_ROOM_ID: None,  # hub-like: contract decides
    HUB_ROOM_ID: None,
}


@dataclass
class RoomDecision:
    room_id: str
    max_members: int
    mode: str = ""
    single_chassis: bool = False


def _hub_max_members(contract: dict[str, Any]) -> int:
    mw = (contract.get("extensions") or {}).get("mw") or {}
    try:
        return max(1, int(mw.get("max_members") or 8))
    except (TypeError, ValueError):
        return 8


def _is_hub_like(level_id: str, contract: dict[str, Any]) -> bool:
    mw = (contract.get("extensions") or {}).get("mw") or {}
    return mw.get("mode") == "hub" or level_id == "demo_hub"


def is_public_room(room_id: str, hub_like: bool) -> bool:
    return hub_like or room_id in PUBLIC_ROOM_CAPS


def decide(
    level_id: str,
    contract: dict[str, Any],
    requested_room_id: str,
    session_id: str,
    requested_mode: str = "",
) -> RoomDecision:
    """Resolve room_id / max_members / mode for a join (legacy parity)."""
    room_id = requested_room_id or session_id
    explicit = bool(requested_room_id)
    hub_like = _is_hub_like(level_id, contract)

    if hub_like:
        max_members = _hub_max_members(contract)
        if not explicit:
            mw = (contract.get("extensions") or {}).get("mw") or {}
            room_id = str(mw.get("default_room_id") or HUB_ROOM_ID)
        return RoomDecision(room_id=room_id, max_members=max_members)

    if level_id == "demo_city":
        if not explicit:
            room_id = CITY_ROOM_ID
        return RoomDecision(room_id=room_id, max_members=CITY_ROOM_MAX)

    if level_id == "demo_race":
        if not explicit:
            room_id = RACE_ROOM_ID
            return RoomDecision(room_id=room_id, max_members=RACE_ROOM_MAX, mode="shared_ffa")
        if room_id == RACE_ROOM_ID:
            return RoomDecision(room_id=room_id, max_members=RACE_ROOM_MAX, mode="shared_ffa")
        if requested_mode == "duel":
            return RoomDecision(room_id=room_id, max_members=RACE_ROOM_MAX, mode="duel")
        return RoomDecision(
            room_id=room_id, max_members=1, mode=requested_mode or "solo", single_chassis=True
        )

    cap = PUBLIC_ROOM_CAPS.get(room_id)
    if cap is not None:
        return RoomDecision(room_id=room_id, max_members=cap)
    return RoomDecision(room_id=room_id, max_members=1)


class Matchmaker:
    """ADR-011 stub: future queue/lobby matching. Always declines."""

    @staticmethod
    def match(level_id: str, profile: dict[str, Any]) -> None:
        return None
