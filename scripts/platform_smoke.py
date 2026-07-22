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
        space_id=None,
        route_kind="mineworld_level",
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
    row = r1.get("row") or {}
    if row.get("route_kind") not in (None, "mineworld_level"):
        print("FAIL: route_kind", row, file=sys.stderr)
        return 1

    r3 = store.record_score(
        session_id="sess-space",
        player_id="demo",
        level_id="demo_workshop",
        outcome="success",
        points=100,
        space_id="space-demo-1",
        route_kind="pms_space",
    )
    if not r3.get("created") or (r3.get("row") or {}).get("space_id") != "space-demo-1":
        print("FAIL: space_id attribution", r3, file=sys.stderr)
        return 1
    lb = store.leaderboard(limit=5)
    if not lb or lb[0]["player_id"] != "demo" or int(lb[0]["total_points"]) != 200:
        print("FAIL: leaderboard", lb, file=sys.stderr)
        return 1
    lb_ws = store.leaderboard(limit=5, level_id="demo_workshop")
    if not lb_ws or int(lb_ws[0]["total_points"]) != 200:
        print("FAIL: leaderboard workshop", lb_ws, file=sys.stderr)
        return 1
    lb_city = store.leaderboard(limit=5, level_id="demo_city")
    if lb_city:
        print("FAIL: empty city board expected", lb_city, file=sys.stderr)
        return 1

    store.record_score(
        session_id="sess-city",
        player_id="demo",
        level_id="demo_city",
        outcome="success",
        points=100,
        duration_sim_s=40.0,
        display_name="Demo Pilot",
    )
    lb_city2 = store.leaderboard(limit=5, level_id="demo_city")
    if not lb_city2 or int(lb_city2[0]["total_points"]) != 100:
        print("FAIL: leaderboard city", lb_city2, file=sys.stderr)
        return 1

    stats = store.player_stats("demo")
    if int(stats.get("total_points") or 0) != 300:
        print("FAIL: player_stats", stats, file=sys.stderr)
        return 1
    hist = store.player_scores("demo", limit=5)
    space_rows = [h for h in hist if h.get("session_id") == "sess-space"]
    if not space_rows or space_rows[0].get("space_id") != "space-demo-1":
        print("FAIL: player_scores space_id", hist, file=sys.stderr)
        return 1

    # E2: admin link + federated stub login
    link = store.link_identity(
        player_id="demo",
        issuer="robohub",
        external_sub="rh-42",
    )
    if link.get("player_id") != "demo":
        print("FAIL: link_identity", link, file=sys.stderr)
        return 1
    linked = store.resolve_identity("robohub", "rh-42")
    if linked is None or linked.player_id != "demo":
        print("FAIL: resolve_identity", file=sys.stderr)
        return 1

    fed = store.ensure_federated_player(
        issuer="stub",
        external_sub="ext-smoke-1",
        display_name="Fed Smoke",
    )
    if not fed.player_id.startswith("fed_stub_"):
        print("FAIL: ensure_federated_player id", fed.player_id, file=sys.stderr)
        return 1
    fed2 = store.ensure_federated_player(issuer="stub", external_sub="ext-smoke-1")
    if fed2.player_id != fed.player_id:
        print("FAIL: federated idempotent", fed2.player_id, file=sys.stderr)
        return 1
    links = store.list_identity_links(fed.player_id)
    if not any(x.get("issuer") == "stub" and x.get("external_sub") == "ext-smoke-1" for x in links):
        print("FAIL: list_identity_links", links, file=sys.stderr)
        return 1

    print("platform smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
