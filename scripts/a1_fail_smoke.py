"""A1: time_limit → outcome=fail + objective_failed (offline, no WS)."""

from __future__ import annotations

import copy
import sys
import uuid
from pathlib import Path
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "gateway"))

from echo_server import (  # noqa: E402
    Session,
    evaluate_objectives,
    evaluate_time_limit,
    load_contract,
)


def main() -> int:
    """Patch workshop time_limit_s short; assert fail event + outcome."""
    contract = load_contract(REPO / "examples" / "contracts" / "demo_workshop.json")
    contract = copy.deepcopy(contract)
    ext = contract.setdefault("extensions", {})
    il = dict(ext.get("mw.il") or {})
    il["time_limit_s"] = 0.05
    il["task_id"] = "obj_place_block"
    ext["mw.il"] = il

    room = SimpleNamespace(tick=3, props={}, mechs={}, mj_data=None)  # 3*0.02 > 0.05
    session = Session(
        session_id=str(uuid.uuid4()),
        ws=None,  # type: ignore[arg-type]
        contract=contract,
        room=room,  # type: ignore[arg-type]
        joined=True,
        level_id="demo_workshop",
    )

    assert evaluate_objectives(session) == []
    events = evaluate_time_limit(session)
    if not events or events[0].get("event_type") != "objective_failed":
        print("FAIL: expected objective_failed", events, file=sys.stderr)
        return 1
    if session.outcome != "fail":
        print(f"FAIL: outcome={session.outcome!r}", file=sys.stderr)
        return 1
    if events[0].get("objective_id") != "obj_place_block":
        print("FAIL: wrong objective_id", events[0], file=sys.stderr)
        return 1
    # Idempotent: already failed.
    if evaluate_time_limit(session):
        print("FAIL: duplicate time_limit events", file=sys.stderr)
        return 1
    print("a1-fail OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
