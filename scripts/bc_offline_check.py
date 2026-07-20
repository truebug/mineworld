"""P1b: minimal BC offline check — success CSV has parseable joints columns."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_CSV = REPO / "recordings" / "exports" / "trajectories.csv"


def _parse_joints(cell: str | None) -> dict | None:
    """Parse joints JSON cell; return dict or None if empty/invalid."""
    if cell is None:
        return None
    raw = str(cell).strip()
    if not raw:
        return None
    try:
        val = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return val if isinstance(val, dict) and val else None


def check_csv(path: Path, *, min_rows: int = 1) -> int:
    """Validate IL CSV for BC: joints present on enough entity-frame rows.

    Returns 0 on success, 1 on failure.
    """
    if not path.is_file():
        print(f"FAIL: missing CSV {path}", file=sys.stderr)
        return 1
    with path.open(encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        if not reader.fieldnames:
            print("FAIL: empty CSV header", file=sys.stderr)
            return 1
        fields = set(reader.fieldnames)
        for need in ("session_id", "entity_id", "joints"):
            if need not in fields:
                print(f"FAIL: missing column {need!r} in {sorted(fields)}", file=sys.stderr)
                return 1
        rows = list(reader)

    with_joints: list[dict] = []
    with_cmd_targets = 0
    joint_keys: set[str] = set()
    for row in rows:
        joints = _parse_joints(row.get("joints"))
        if joints is None:
            continue
        with_joints.append(row)
        joint_keys.update(joints.keys())
        targets = row.get("cmd_joint_targets")
        if targets and str(targets).strip():
            with_cmd_targets += 1

    if len(with_joints) < min_rows:
        print(
            f"FAIL: need ≥{min_rows} rows with joints, got {len(with_joints)} "
            f"(total rows={len(rows)})",
            file=sys.stderr,
        )
        return 1

    print(
        f"bc-offline OK rows={len(rows)} with_joints={len(with_joints)} "
        f"cmd_joint_targets={with_cmd_targets} joint_keys={sorted(joint_keys)[:12]}"
    )
    return 0


def main() -> int:
    """CLI: check an existing success export CSV for BC-ready joints."""
    parser = argparse.ArgumentParser(description="P1b minimal BC offline joints check")
    parser.add_argument(
        "--csv",
        type=Path,
        default=DEFAULT_CSV,
        help="Trajectory CSV (default: recordings/exports/trajectories.csv)",
    )
    parser.add_argument(
        "--min-rows",
        type=int,
        default=1,
        help="Minimum rows with non-empty joints JSON (default: 1)",
    )
    parser.add_argument(
        "--export-first",
        action="store_true",
        help="Run export_trajectories (outcome=success) into --csv before check",
    )
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=REPO / "recordings" / "sessions",
        help="Sessions root when using --export-first",
    )
    args = parser.parse_args()
    out = args.csv.resolve()

    if args.export_first:
        sys.path.insert(0, str(REPO / "gateway"))
        from recording_store import export_trajectories  # noqa: WPS433

        n = export_trajectories(
            args.sessions_dir.resolve(),
            out,
            format="csv",
            outcome="success",
        )
        print(f"exported {n} row(s) -> {out}")

    return check_csv(out, min_rows=max(1, args.min_rows))


if __name__ == "__main__":
    raise SystemExit(main())
