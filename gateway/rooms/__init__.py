"""Room policy registry (ADR-011): per-level capacity / default room / mode."""
from .policy import (
    CHESS_ROOM_ID,
    CITY_ROOM_ID,
    CITY_ROOM_MAX,
    DEMO_ROOM_ID,
    DEMO_ROOM_MAX,
    HUB_ROOM_ID,
    RACE_MODES,
    RACE_ROOM_ID,
    RACE_ROOM_MAX,
    RoomDecision,
    decide,
    is_public_room,
)

__all__ = [
    "CHESS_ROOM_ID",
    "CITY_ROOM_ID",
    "CITY_ROOM_MAX",
    "DEMO_ROOM_ID",
    "DEMO_ROOM_MAX",
    "HUB_ROOM_ID",
    "RACE_MODES",
    "RACE_ROOM_ID",
    "RACE_ROOM_MAX",
    "RoomDecision",
    "decide",
    "is_public_room",
]
