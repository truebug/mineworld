"""Export recorded entity base_pose trajectories to CSV or JSONL."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "gateway") not in sys.path:
    sys.path.insert(0, str(REPO / "gateway"))

from recording_store import DB_PATH, SESSIONS_ROOT, export_trajectories, rebuild_sqlite  # noqa: E402


def main() -> None:
    """CLI entry: optional reindex, then export trajectories."""
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
    args = parser.parse_args()

    sessions_dir = args.sessions_dir.resolve()
    out_path = args.out.resolve()
    fmt = args.format
    if fmt is None:
        fmt = "jsonl" if out_path.suffix.lower() == ".jsonl" else "csv"

    if args.rebuild_index:
        count = rebuild_sqlite(sessions_dir, DB_PATH)
        print(f"reindexed {count} session(s) -> {DB_PATH}")

    rows = export_trajectories(sessions_dir, out_path, format=fmt)
    print(f"exported {rows} row(s) -> {out_path}")


if __name__ == "__main__":
    main()
