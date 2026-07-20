"""HTTP handlers for /api/platform/* (stdlib; mount in web server or api_server)."""

from __future__ import annotations

import json
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse

from mw_platform.config import admin_key, auth_enabled, db_url, gateway_key
from mw_platform.scoring import compute_points
from mw_platform.store import ensure_demo_player, get_store, player_to_json

SendJson = Callable[[Any, int], None]
ReadBody = Callable[[], dict[str, Any] | None]
GetHeader = Callable[[str], str | None]


def _bearer_token(get_header: GetHeader) -> str | None:
    auth = get_header("Authorization") or get_header("authorization") or ""
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return None


def _player_from_request(get_header: GetHeader):
    token = _bearer_token(get_header)
    if not token:
        return None
    return get_store().resolve_token(token)


def _gateway_or_admin(get_header: GetHeader) -> bool:
    """True if X-Gateway-Key or X-Admin-Key matches."""
    gw = get_header("X-Gateway-Key") or get_header("x-gateway-key")
    expected_gw = gateway_key()
    if expected_gw and gw == expected_gw:
        return True
    key = get_header("X-Admin-Key") or get_header("x-admin-key")
    expected = admin_key()
    return bool(expected and key == expected)


def handle_platform_get(
    path: str,
    *,
    send_json: SendJson,
    get_header: GetHeader,
) -> bool:
    """Return True if request was handled."""
    if path == "/api/platform/health":
        send_json({"ok": True, "auth_enabled": auth_enabled(), "db": db_url()}, 200)
        return True
    if path == "/api/platform/me":
        player = _player_from_request(get_header)
        if player is None:
            send_json({"error": "unauthorized"}, 401)
            return True
        store = get_store()
        stats = store.player_stats(player.player_id)  # type: ignore[attr-defined]
        scores = store.player_scores(player.player_id, limit=20)  # type: ignore[attr-defined]
        send_json(
            {
                "ok": True,
                "player": player_to_json(player),
                "stats": stats,
                "scores": scores,
            },
            200,
        )
        return True
    if path == "/api/platform/leaderboard":
        store = get_store()
        rows = store.leaderboard(limit=10)  # type: ignore[attr-defined]
        send_json({"ok": True, "entries": rows}, 200)
        return True
    if path == "/api/platform/players":
        key = get_header("X-Admin-Key") or get_header("x-admin-key")
        expected = admin_key()
        if not expected or key != expected:
            send_json({"error": "forbidden"}, 403)
            return True
        players = [player_to_json(p) for p in get_store().list_players()]
        send_json({"ok": True, "players": players}, 200)
        return True
    return False


def handle_platform_post(
    path: str,
    *,
    send_json: SendJson,
    read_body: ReadBody,
    get_header: GetHeader,
) -> bool:
    """Return True if request was handled."""
    if path == "/api/platform/login":
        body = read_body()
        if body is None:
            send_json({"error": "bad_json"}, 400)
            return True
        pid = str(body.get("player_id", "")).strip()
        password = str(body.get("password", ""))
        if not pid or not password:
            send_json({"error": "missing_credentials"}, 400)
            return True
        store = get_store()
        player = store.verify_password(pid, password)
        if player is None:
            send_json({"error": "invalid_login"}, 401)
            return True
        token = store.issue_token(player.player_id)
        send_json(
            {"ok": True, "token": token, "player": player_to_json(player)},
            200,
        )
        return True

    if path == "/api/platform/logout":
        token = _bearer_token(get_header)
        if token:
            get_store().revoke_token(token)
        send_json({"ok": True}, 200)
        return True

    if path == "/api/platform/scores":
        if not _gateway_or_admin(get_header):
            send_json({"error": "forbidden"}, 403)
            return True
        body = read_body()
        if body is None:
            send_json({"error": "bad_json"}, 400)
            return True
        sid = str(body.get("session_id", "")).strip()
        pid = str(body.get("player_id", "")).strip()
        level_id = str(body.get("level_id", "")).strip()
        outcome = str(body.get("outcome", "")).strip() or "success"
        if not sid or not pid or not level_id:
            send_json({"error": "missing_fields"}, 400)
            return True
        try:
            duration = float(body.get("duration_sim_s") or 0.0)
        except (TypeError, ValueError):
            duration = 0.0
        task_id = body.get("task_id")
        task_id_s = str(task_id).strip() if task_id else None
        display = body.get("display_name")
        display_s = str(display).strip() if display else None
        if "points" in body and body["points"] is not None:
            try:
                points = int(body["points"])
            except (TypeError, ValueError):
                send_json({"error": "bad_points"}, 400)
                return True
        else:
            points = compute_points(
                level_id=level_id, outcome=outcome, duration_sim_s=duration
            )
        try:
            result = get_store().record_score(  # type: ignore[attr-defined]
                session_id=sid,
                player_id=pid,
                level_id=level_id,
                outcome=outcome,
                points=points,
                duration_sim_s=duration,
                task_id=task_id_s,
                display_name=display_s,
            )
        except ValueError as exc:
            send_json({"error": str(exc)}, 400)
            return True
        status = 201 if result.get("created") else 200
        send_json({"ok": True, "created": result.get("created"), "score": result.get("row")}, status)
        return True

    if path == "/api/platform/admin/players":
        key = get_header("X-Admin-Key") or get_header("x-admin-key")
        expected = admin_key()
        if not expected or key != expected:
            send_json({"error": "forbidden"}, 403)
            return True
        body = read_body()
        if body is None:
            send_json({"error": "bad_json"}, 400)
            return True
        pid = str(body.get("player_id", "")).strip()
        display = str(body.get("display_name", pid)).strip()
        password = str(body.get("password", ""))
        accent = str(body.get("accent", "#4aa3ff"))
        if not pid or not password:
            send_json({"error": "missing_fields"}, 400)
            return True
        try:
            player = get_store().create_player(pid, display, password, accent=accent)
        except ValueError as exc:
            send_json({"error": str(exc)}, 409)
            return True
        send_json({"ok": True, "player": player_to_json(player)}, 201)
        return True

    return False


def init_platform_data() -> None:
    """Ensure schema + demo account."""
    store = get_store()
    store.ensure_schema()
    ensure_demo_player(store)
