#!/usr/bin/env python3
"""Smoke test platform API (Phase A + B · identity / scores)."""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

from mw_platform.handlers import init_platform_data  # noqa: E402
from mw_platform.scoring import compute_points  # noqa: E402
from mw_platform.store import get_store  # noqa: E402


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="mw_platform_smoke_")
    db_path = Path(tmp) / "test.sqlite"
    os.environ["MW_PLATFORM_DB_URL"] = f"sqlite:///{db_path}"
    import mw_platform.store as store_mod

    store_mod._STORE = None  # noqa: SLF001
    init_platform_data()

    store = get_store()
    player = store.verify_password("demo", "demo")
    if player is None:
        print("FAIL: demo login", file=sys.stderr)
        return 1
    token = store.issue_token(player.player_id)
    resolved = store.resolve_token(token)
    if resolved is None or resolved.player_id != "demo":
        print("FAIL: token resolve", file=sys.stderr)
        return 1

    if compute_points(level_id="demo_workshop", outcome="success") != 100:
        print("FAIL: workshop points", file=sys.stderr)
        return 1
    if compute_points(level_id="demo_city", outcome="success", duration_sim_s=50) != 100:
        print("FAIL: city points", file=sys.stderr)
        return 1

    r1 = store.record_score(
        session_id="sess-a",
        player_id="demo",
        level_id="demo_workshop",
        outcome="success",
        points=100,
        display_name="Demo Pilot",
    )
    r2 = store.record_score(
        session_id="sess-a",
        player_id="demo",
        level_id="demo_workshop",
        outcome="success",
        points=100,
    )
    if not r1.get("created") or r2.get("created"):
        print("FAIL: score idempotent", file=sys.stderr)
        return 1
    lb = store.leaderboard(limit=5)
    if not lb or lb[0]["player_id"] != "demo" or int(lb[0]["total_points"]) != 100:
        print("FAIL: leaderboard", lb, file=sys.stderr)
        return 1

    print("platform smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
