#!/usr/bin/env python3
"""Smoke test platform API (Phase A · PL1 / ID1)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

from mw_platform.handlers import init_platform_data  # noqa: E402
from mw_platform.store import get_store  # noqa: E402


def _post(base: str, path: str, body: dict, headers: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode("utf-8")
    hdrs = {"Content-Type": "application/json", **(headers or {})}
    req = urllib.request.Request(base + path, data=data, headers=hdrs, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def _get(base: str, path: str, headers: dict | None = None) -> tuple[int, dict]:
    req = urllib.request.Request(base + path, headers=headers or {}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def main() -> int:
    tmp = tempfile.mkdtemp(prefix="mw_platform_smoke_")
    db_path = Path(tmp) / "test.sqlite"
    os.environ["MW_PLATFORM_DB_URL"] = f"sqlite:///{db_path}"
    # Reset singleton
    import mw_platform.store as store_mod

    store_mod._STORE = None  # noqa: SLF001
    init_platform_data()

    # In-process handler smoke (no server)
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

    print("platform smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
