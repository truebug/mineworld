"""SC1 score model v0 — pure functions, no I/O."""

from __future__ import annotations

from typing import Any


def compute_points(
    *,
    level_id: str,
    outcome: str,
    duration_sim_s: float = 0.0,
) -> int:
    """Return points for a finished session (0 if not scored).

    Workshop (demo_workshop / tutorial*): success → 100.
    City / racing (demo_city / demo_race): success → max(10, 200 - floor(duration * 2)).
    Hub and non-success → 0.
    """
    if outcome != "success":
        return 0
    lid = (level_id or "").strip()
    if lid in ("demo_hub",):
        return 0
    if lid in ("demo_workshop",) or lid.startswith("tutorial"):
        return 100
    if lid in ("demo_city", "demo_race"):
        # Faster clear → higher score; floor at 10.
        return max(10, 200 - int(duration_sim_s * 2.0))
    # Unknown playable level: small success credit.
    return 50


def score_payload(
    *,
    session_id: str,
    player_id: str,
    level_id: str,
    outcome: str,
    duration_sim_s: float = 0.0,
    task_id: str | None = None,
    display_name: str | None = None,
    space_id: str | None = None,
    route_kind: str | None = None,
) -> dict[str, Any]:
    """Build API body including computed points."""
    points = compute_points(
        level_id=level_id, outcome=outcome, duration_sim_s=duration_sim_s
    )
    body: dict[str, Any] = {
        "session_id": session_id,
        "player_id": player_id,
        "level_id": level_id,
        "outcome": outcome,
        "duration_sim_s": round(float(duration_sim_s), 3),
        "task_id": task_id,
        "display_name": display_name,
        "points": points,
        "route_kind": (route_kind or "mineworld_level").strip() or "mineworld_level",
    }
    sid = (space_id or "").strip()
    if sid:
        body["space_id"] = sid
    return body
