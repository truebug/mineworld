"""Replay a recorded MineWorld session: base-trajectory stats + x-y plot.

Reads `header.json` + `frames.jsonl` (schemas/recording-session.v0.json).
Plots with matplotlib when installed (PNG via Agg); otherwise falls back
to an ASCII plot so the script always works in a bare venv.

Usage:
    python scripts/replay_xy.py recordings/sessions/<session_id>
    python scripts/replay_xy.py examples/recordings --entity mech_player
    python scripts/replay_xy.py <dir> --out /tmp/xy.png   # force PNG path
    python scripts/replay_xy.py <dir> --ascii             # force ASCII plot
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path


def load_session(path: Path) -> tuple[dict, list[dict]]:
    if path.is_file():
        frames_path = path
        header_path = path.with_name("header.json")
    else:
        frames_path = path / "frames.jsonl"
        header_path = path / "header.json"
    if not frames_path.exists():
        raise SystemExit(f"frames.jsonl not found at {frames_path}")
    header = {}
    if header_path.exists():
        header = json.loads(header_path.read_text(encoding="utf-8"))
    frames = []
    with frames_path.open(encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                frames.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{frames_path}:{lineno}: invalid JSON: {exc}")
    return header, frames


def extract_track(frames: list[dict], entity: str | None) -> tuple[str, list[tuple[float, float, float]]]:
    """Return (entity_id, [(t_sim, x, y), ...]) for the entity."""
    available: list[str] = []
    track: list[tuple[float, float, float]] = []
    for frame in frames:
        state = frame.get("state") or {}
        for ent in state.get("entities") or []:
            eid = str(ent.get("entity_id", ""))
            if eid and eid not in available:
                available.append(eid)
            want = entity if entity else (available[0] if available else None)
            if eid == want:
                pose = ent.get("base_pose") or {}
                track.append(
                    (
                        float(frame.get("t_sim", 0.0)),
                        float(pose.get("x", 0.0)),
                        float(pose.get("y", 0.0)),
                    )
                )
    if entity and entity not in available:
        raise SystemExit(f"entity '{entity}' not found; available: {available}")
    if not track:
        raise SystemExit("no entity states found in frames")
    return (entity or available[0]), track


def print_stats(header: dict, entity: str, track: list[tuple[float, float, float]]) -> None:
    distance = sum(
        math.hypot(track[i][1] - track[i - 1][1], track[i][2] - track[i - 1][2])
        for i in range(1, len(track))
    )
    displacement = math.hypot(track[-1][1] - track[0][1], track[-1][2] - track[0][2])
    duration = track[-1][0] - track[0][0]
    print(f"session: {header.get('session_id', '?')}  level: {header.get('level_id', '?')}")
    print(f"entity:  {entity}")
    print(f"frames:  {len(track)}  duration: {duration:.2f}s  dt: {header.get('dt', '?')}")
    print(f"start:   ({track[0][1]:.3f}, {track[0][2]:.3f})")
    print(f"end:     ({track[-1][1]:.3f}, {track[-1][2]:.3f})")
    print(f"distance: {distance:.3f} m  displacement: {displacement:.3f} m")


def ascii_plot(track: list[tuple[float, float, float]], width: int = 64, height: int = 24) -> None:
    xs = [p[1] for p in track]
    ys = [p[2] for p in track]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    pad_x = (x1 - x0) * 0.05 or 0.5
    pad_y = (y1 - y0) * 0.05 or 0.5
    x0, x1, y0, y1 = x0 - pad_x, x1 + pad_x, y0 - pad_y, y1 + pad_y
    grid = [[" "] * width for _ in range(height)]

    def cell(x: float, y: float) -> tuple[int, int]:
        col = min(width - 1, int((x - x0) / (x1 - x0) * (width - 1)))
        row = min(height - 1, int((y1 - y) / (y1 - y0) * (height - 1)))
        return row, col

    for _, x, y in track:
        row, col = cell(x, y)
        grid[row][col] = "*"
    r0, c0 = cell(track[0][1], track[0][2])
    r1, c1 = cell(track[-1][1], track[-1][2])
    grid[r0][c0] = "S"
    grid[r1][c1] = "E"

    print(f"\nx-y track (x: {x0:.2f}..{x1:.2f} m, y: {y0:.2f}..{y1:.2f} m; S=start E=end)")
    print("+" + "-" * width + "+")
    for row in grid:
        print("|" + "".join(row) + "|")
    print("+" + "-" * width + "+")


def png_plot(track: list[tuple[float, float, float]], entity: str, out: Path, show: bool) -> bool:
    try:
        import matplotlib

        if not show:
            matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return False
    fig, ax = plt.subplots(figsize=(7, 5))
    ax.plot([p[1] for p in track], [p[2] for p in track], "-", lw=1.5, label=entity)
    ax.plot(track[0][1], track[0][2], "o", color="green", label="start")
    ax.plot(track[-1][1], track[-1][2], "s", color="red", label="end")
    ax.set_xlabel("x [m]")
    ax.set_ylabel("y [m]")
    ax.set_title("MineWorld session replay (base x-y)")
    ax.axis("equal")
    ax.grid(True, alpha=0.3)
    ax.legend()
    fig.tight_layout()
    if show:
        plt.show()
    else:
        fig.savefig(out, dpi=120)
        print(f"plot saved: {out}")
    plt.close(fig)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Replay session: stats + x-y plot")
    parser.add_argument("session", type=Path, help="session dir or frames.jsonl")
    parser.add_argument("--entity", default=None, help="entity_id (default: first seen)")
    parser.add_argument("--out", type=Path, default=None, help="PNG output path")
    parser.add_argument("--show", action="store_true", help="open GUI window instead of PNG")
    parser.add_argument("--ascii", action="store_true", help="force ASCII plot")
    args = parser.parse_args()

    header, frames = load_session(args.session)
    entity, track = extract_track(frames, args.entity)
    print_stats(header, entity, track)

    out = args.out
    if out is None:
        base = args.session if args.session.is_dir() else args.session.parent
        out = base / "replay_xy.png"
    plotted = False
    if not args.ascii:
        plotted = png_plot(track, entity, out, args.show)
        if not plotted:
            print("matplotlib not installed; falling back to ASCII plot "
                  "(pip install matplotlib for PNG)")
    if args.ascii or not plotted:
        ascii_plot(track)


if __name__ == "__main__":
    sys.exit(main())
