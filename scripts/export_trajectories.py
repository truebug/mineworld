"""Export recorded entity trajectories to CSV or JSONL (IL filters V3b/V4b)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "gateway") not in sys.path:
    sys.path.insert(0, str(REPO / "gateway"))

from recording_store import DB_PATH, SESSIONS_ROOT, export_trajectories, rebuild_sqlite  # noqa: E402


def main() -> None:
    """CLI entry: optional reindex, then export trajectories with IL filters."""
    parser = argparse.ArgumentParser(description="Export MineWorld session trajectories")
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=SESSIONS_ROOT,
        help="Session recording root (header.json + frames.jsonl)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO / "recordings" / "exports" / "trajectories.csv",
        help="Output file path (.csv or .jsonl)",
    )
    parser.add_argument(
        "--format",
        choices=("csv", "jsonl"),
        default=None,
        help="Output format (default: infer from --out suffix)",
    )
    parser.add_argument(
        "--rebuild-index",
        action="store_true",
        help="Rebuild recordings/index.sqlite before export",
    )
    parser.add_argument(
        "--level-id",
        default=None,
        help="Only sessions with this level_id",
    )
    parser.add_argument(
        "--task-id",
        default=None,
        help="Only sessions with this task_id",
    )
    parser.add_argument(
        "--outcome",
        default="success",
        help="Filter by outcome (default: success; use 'all' for no filter)",
    )
    parser.add_argument(
        "--player-id",
        default=None,
        help="Only sessions with this player_id (AD2)",
    )
    args = parser.parse_args()

    sessions_dir = args.sessions_dir.resolve()
    out_path = args.out.resolve()
    fmt = args.format
    if fmt is None:
        fmt = "jsonl" if out_path.suffix.lower() == ".jsonl" else "csv"

    if args.rebuild_index:
        count = rebuild_sqlite(sessions_dir, DB_PATH)
        print(f"reindexed {count} session(s) -> {DB_PATH}")

    rows = export_trajectories(
        sessions_dir,
        out_path,
        format=fmt,
        level_id=args.level_id,
        task_id=args.task_id,
        outcome=args.outcome,
        player_id=args.player_id,
    )
    print(f"exported {rows} row(s) -> {out_path}")


if __name__ == "__main__":
    main()
