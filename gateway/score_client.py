"""Post session scores to platform API (SC2). Fire-and-forget from Gateway."""

from __future__ import annotations

import json
import logging
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

LOG = logging.getLogger("mineworld.score_client")

_REPO = Path(__file__).resolve().parents[1]
if str(_REPO) not in sys.path:
    sys.path.insert(0, str(_REPO))

from mw_platform.scoring import compute_points, score_payload  # noqa: E402


def _score_url() -> str:
    return os.environ.get(
        "MW_PLATFORM_SCORE_URL",
        "http://127.0.0.1:8080/api/platform/scores",
    )


def _gateway_key() -> str:
    return (
        os.environ.get("MW_PLATFORM_GATEWAY_KEY")
        or os.environ.get("MW_PLATFORM_ADMIN_KEY")
        or "mineworld-gateway-dev"
    )


def build_and_post(
    *,
    session_id: str,
    player_id: str,
    level_id: str,
    outcome: str,
    duration_sim_s: float = 0.0,
    task_id: str | None = None,
    display_name: str | None = None,
) -> bool:
    """Compute points and POST; skip when 0 points or missing player_id."""
    pid = (player_id or "").strip()
    if not pid or pid.startswith("local-"):
        LOG.debug("score skip: no platform player_id")
        return False
    payload = score_payload(
        session_id=session_id,
        player_id=pid,
        level_id=level_id,
        outcome=outcome,
        duration_sim_s=duration_sim_s,
        task_id=task_id,
        display_name=display_name,
    )
    return post_score(payload)


def post_score(payload: dict[str, Any], *, timeout_s: float = 2.0) -> bool:
    """POST score JSON; return True on 2xx. Never raises to caller."""
    if int(payload.get("points") or 0) <= 0:
        return False
    url = _score_url()
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "X-Gateway-Key": _gateway_key(),
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            ok = 200 <= int(resp.status) < 300
            if ok:
                LOG.info(
                    "score posted session=%s player=%s points=%s",
                    payload.get("session_id"),
                    payload.get("player_id"),
                    payload.get("points"),
                )
            return ok
    except urllib.error.HTTPError as exc:
        body = exc.read()[:200] if exc.fp else b""
        LOG.warning("score post HTTP %s: %s", exc.code, body)
        return False
    except Exception as exc:  # noqa: BLE001 — network optional
        LOG.warning("score post failed: %s", exc)
        return False
