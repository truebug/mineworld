"""A3: catalog loads solo IL template variants; scoring treats tutorial* as workshop."""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "gateway"))
sys.path.insert(0, str(REPO))

from echo_server import catalog_contracts  # noqa: E402
from mw_platform.scoring import compute_points  # noqa: E402


def main() -> int:
    """Assert near/tight variants present with time_limit + shared template id."""
    cats = catalog_contracts(REPO / "examples" / "contracts")
    for lid in ("demo_workshop", "tutorial_place_near", "tutorial_place_tight"):
        if lid not in cats:
            print(f"FAIL: missing {lid}", file=sys.stderr)
            return 1
    for lid in ("tutorial_place_near", "tutorial_place_tight"):
        data = __import__("json").loads(cats[lid].read_text(encoding="utf-8"))
        il = (data.get("extensions") or {}).get("mw.il") or {}
        if il.get("template") != "solo_il_place_v0":
            print(f"FAIL: {lid} template", il, file=sys.stderr)
            return 1
        if not il.get("time_limit_s"):
            print(f"FAIL: {lid} time_limit", il, file=sys.stderr)
            return 1
        if il.get("task_id") != "obj_place_block":
            print(f"FAIL: {lid} task_id", il, file=sys.stderr)
            return 1
        if compute_points(level_id=lid, outcome="success") != 100:
            print(f"FAIL: scoring {lid}", file=sys.stderr)
            return 1
    print("a3-catalog OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
