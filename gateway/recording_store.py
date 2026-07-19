"""Filesystem recording index and trajectory export (POC data-side tooling)."""

from __future__ import annotations

import csv
import io
import json
import logging
import sqlite3
from pathlib import Path
from typing import Any, TextIO

LOG = logging.getLogger("mineworld.recording_store")

REPO_ROOT = Path(__file__).resolve().parents[1]
SESSIONS_ROOT = REPO_ROOT / "recordings" / "sessions"
DB_PATH = REPO_ROOT / "recordings" / "index.sqlite"

CSV_COLUMNS = (
    "session_id",
    "tick",
    "t_sim",
    "entity_id",
    "x",
    "y",
    "z",
    "yaw",
    "cmd_vx",
)


def _read_header(header_path: Path) -> dict[str, Any] | None:
    """Load header.json; return None on missing or invalid."""
    try:
        return json.loads(header_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _session_summary(child: Path, header: dict[str, Any], *, has_frames: bool) -> dict[str, Any]:
    """Build one list_sessions row from a parsed header."""
    stats = header.get("stats") or {}
    features = header.get("features") or []
    return {
        "session_id": header.get("session_id") or child.name,
        "level_id": header.get("level_id"),
        "task_id": header.get("task_id"),
        "difficulty": header.get("difficulty"),
        "control_mode": header.get("control_mode"),
        "control_modes": header.get("control_modes") or [],
        "outcome": header.get("outcome"),
        "started_at": header.get("started_at"),
        "ended_at": header.get("ended_at"),
        "duration_sim_s": stats.get("duration_sim_s"),
        "num_frames": stats.get("num_frames"),
        "features": list(features),
        "has_frames": has_frames,
        "seed": header.get("seed"),
    }


def list_sessions(root: Path) -> list[dict[str, Any]]:
    """Scan sessions/* and return summary dicts (newest started_at first)."""
    if not root.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for child in root.iterdir():
        if not child.is_dir():
            continue
        header_path = child / "header.json"
        if not header_path.is_file():
            continue
        header = _read_header(header_path)
        if header is None:
            continue
        out.append(
            _session_summary(child, header, has_frames=(child / "frames.jsonl").is_file())
        )
    out.sort(key=lambda s: str(s.get("started_at") or ""), reverse=True)
    return out


def _session_index_row(child: Path, header: dict[str, Any], *, has_frames: bool) -> dict[str, Any]:
    """Extend list summary with sqlite-only columns."""
    row = _session_summary(child, header, has_frames=has_frames)
    row["contract_hash"] = header.get("contract_hash")
    return row


def rebuild_sqlite(root: Path, db_path: Path) -> int:
    """Rebuild index.sqlite from header.json files; return inserted row count."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("DROP TABLE IF EXISTS sessions")
        conn.execute(
            """
            CREATE TABLE sessions (
                session_id TEXT PRIMARY KEY,
                level_id TEXT,
                task_id TEXT,
                difficulty TEXT,
                control_mode TEXT,
                control_modes TEXT,
                outcome TEXT,
                started_at TEXT,
                ended_at TEXT,
                duration_sim_s REAL,
                num_frames INTEGER,
                features TEXT,
                has_frames INTEGER,
                contract_hash TEXT,
                seed INTEGER
            )
            """
        )
        rows = []
        for child in root.iterdir() if root.is_dir() else []:
            if not child.is_dir():
                continue
            header_path = child / "header.json"
            if not header_path.is_file():
                continue
            header = _read_header(header_path)
            if header is None:
                continue
            summary = _session_index_row(
                child,
                header,
                has_frames=(child / "frames.jsonl").is_file(),
            )
            rows.append(
                (
                    summary["session_id"],
                    summary.get("level_id"),
                    summary.get("task_id"),
                    summary.get("difficulty"),
                    summary.get("control_mode"),
                    json.dumps(summary.get("control_modes") or [], ensure_ascii=False),
                    summary.get("outcome"),
                    summary.get("started_at"),
                    summary.get("ended_at"),
                    summary.get("duration_sim_s"),
                    summary.get("num_frames"),
                    json.dumps(summary.get("features") or [], ensure_ascii=False),
                    1 if summary.get("has_frames") else 0,
                    summary.get("contract_hash"),
                    summary.get("seed"),
                )
            )
        conn.executemany(
            """
            INSERT OR REPLACE INTO sessions (
                session_id, level_id, task_id, difficulty, control_mode, control_modes,
                outcome, started_at, ended_at, duration_sim_s, num_frames, features,
                has_frames, contract_hash, seed
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        conn.commit()
        return len(rows)
    finally:
        conn.close()


def _cmd_vx(cmd: Any) -> float | None:
    """Extract vx from a recorded cmd object, if present."""
    if not isinstance(cmd, dict):
        return None
    if "vx" not in cmd:
        return None
    try:
        return float(cmd["vx"])
    except (TypeError, ValueError):
        return None


def _iter_trajectory_rows(session_id: str, frames_path: Path) -> list[dict[str, Any]]:
    """Parse frames.jsonl into flat entity pose rows; empty on failure."""
    rows: list[dict[str, Any]] = []
    try:
        with frames_path.open(encoding="utf-8") as fp:
            for line in fp:
                line = line.strip()
                if not line:
                    continue
                frame = json.loads(line)
                tick = frame.get("tick")
                t_sim = frame.get("t_sim")
                cmd = frame.get("cmd")
                cmd_vx = _cmd_vx(cmd)
                state = frame.get("state") or {}
                for ent in state.get("entities") or []:
                    entity_id = ent.get("entity_id")
                    if not entity_id:
                        continue
                    pose = ent.get("base_pose") or {}
                    row: dict[str, Any] = {
                        "session_id": session_id,
                        "tick": tick,
                        "t_sim": t_sim,
                        "entity_id": entity_id,
                        "x": pose.get("x"),
                        "y": pose.get("y"),
                        "z": pose.get("z"),
                        "yaw": pose.get("yaw"),
                    }
                    if cmd_vx is not None:
                        row["cmd_vx"] = cmd_vx
                    rows.append(row)
    except (OSError, json.JSONDecodeError) as exc:
        LOG.warning("skip broken session=%s frames: %s", session_id, exc)
        return []
    return rows


def _write_csv(rows: list[dict[str, Any]], out_fp: TextIO) -> None:
    """Write trajectory rows as CSV."""
    writer = csv.DictWriter(out_fp, fieldnames=CSV_COLUMNS, extrasaction="ignore")
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


def _write_jsonl(rows: list[dict[str, Any]], out_fp: TextIO) -> None:
    """Write trajectory rows as JSONL (one entity-frame per line)."""
    for row in rows:
        out_fp.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")


def collect_trajectory_rows(root: Path) -> list[dict[str, Any]]:
    """Collect entity base_pose rows from all sessions that have frames.jsonl."""
    all_rows: list[dict[str, Any]] = []
    for child in sorted(root.iterdir()) if root.is_dir() else []:
        if not child.is_dir():
            continue
        frames_path = child / "frames.jsonl"
        if not frames_path.is_file():
            continue
        header = _read_header(child / "header.json")
        session_id = (header or {}).get("session_id") or child.name
        all_rows.extend(_iter_trajectory_rows(session_id, frames_path))
    return all_rows


def export_trajectories_text(root: Path, *, format: str = "csv") -> str:
    """Build trajectory export as a string (CSV or JSONL)."""
    fmt = format.lower()
    if fmt not in ("csv", "jsonl"):
        raise ValueError(f"unsupported format: {format!r}")
    rows = collect_trajectory_rows(root)
    buf = io.StringIO()
    if fmt == "csv":
        _write_csv(rows, buf)
    else:
        _write_jsonl(rows, buf)
    return buf.getvalue()


def export_trajectories(
    root: Path,
    out_path: Path,
    *,
    format: str = "csv",
) -> int:
    """Export base_pose trajectories for all sessions with frames.jsonl.

    Returns the number of entity-frame rows written. Skips broken sessions.
    """
    rows = collect_trajectory_rows(root)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as out_fp:
        if format.lower() == "jsonl":
            _write_jsonl(rows, out_fp)
        else:
            _write_csv(rows, out_fp)
    return len(rows)
