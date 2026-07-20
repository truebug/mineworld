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
    "cmd_vy",
    "cmd_yaw_rate",
    "cmd_joint_targets",
    "joints",
    "level_id",
    "task_id",
    "outcome",
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


def _cmd_float(cmd: Any, key: str) -> float | None:
    """Extract a float field from a recorded cmd object, if present."""
    if not isinstance(cmd, dict) or key not in cmd:
        return None
    try:
        return float(cmd[key])
    except (TypeError, ValueError):
        return None


def _json_cell(value: Any) -> str | None:
    """Serialize dict/list values as compact JSON for CSV cells."""
    if value is None:
        return None
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return str(value)


def _header_matches(
    header: dict[str, Any],
    *,
    level_id: str | None,
    task_id: str | None,
    outcome: str | None,
) -> bool:
    """Return True if header passes optional IL filters (V3b / V4b)."""
    if level_id and str(header.get("level_id") or "") != level_id:
        return False
    if task_id and str(header.get("task_id") or "") != task_id:
        return False
    if outcome and outcome != "all":
        if str(header.get("outcome") or "") != outcome:
            return False
    return True


def _iter_trajectory_rows(
    session_id: str,
    frames_path: Path,
    *,
    header: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Parse frames.jsonl into flat entity pose + cmd/joints rows (V1d / V4b)."""
    rows: list[dict[str, Any]] = []
    meta = header or {}
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
                cmd_vx = _cmd_float(cmd, "vx")
                cmd_vy = _cmd_float(cmd, "vy")
                cmd_yaw = _cmd_float(cmd, "yaw_rate")
                cmd_targets = None
                if isinstance(cmd, dict) and isinstance(cmd.get("joint_targets"), dict):
                    cmd_targets = cmd.get("joint_targets")
                state = frame.get("state") or {}
                for ent in state.get("entities") or []:
                    entity_id = ent.get("entity_id")
                    if not entity_id:
                        continue
                    pose = ent.get("base_pose") or {}
                    joints = ent.get("joints") if isinstance(ent.get("joints"), dict) else None
                    row: dict[str, Any] = {
                        "session_id": session_id,
                        "tick": tick,
                        "t_sim": t_sim,
                        "entity_id": entity_id,
                        "x": pose.get("x"),
                        "y": pose.get("y"),
                        "z": pose.get("z"),
                        "yaw": pose.get("yaw"),
                        "level_id": meta.get("level_id"),
                        "task_id": meta.get("task_id"),
                        "outcome": meta.get("outcome"),
                    }
                    if cmd_vx is not None:
                        row["cmd_vx"] = cmd_vx
                    if cmd_vy is not None:
                        row["cmd_vy"] = cmd_vy
                    if cmd_yaw is not None:
                        row["cmd_yaw_rate"] = cmd_yaw
                    if cmd_targets is not None:
                        row["cmd_joint_targets"] = _json_cell(cmd_targets)
                    if joints is not None:
                        row["joints"] = _json_cell(joints)
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


def collect_trajectory_rows(
    root: Path,
    *,
    level_id: str | None = None,
    task_id: str | None = None,
    outcome: str | None = "success",
) -> list[dict[str, Any]]:
    """Collect entity rows from sessions matching IL filters (default: success only)."""
    all_rows: list[dict[str, Any]] = []
    for child in sorted(root.iterdir()) if root.is_dir() else []:
        if not child.is_dir():
            continue
        frames_path = child / "frames.jsonl"
        if not frames_path.is_file():
            continue
        header = _read_header(child / "header.json") or {}
        if not _header_matches(header, level_id=level_id, task_id=task_id, outcome=outcome):
            continue
        session_id = header.get("session_id") or child.name
        all_rows.extend(_iter_trajectory_rows(session_id, frames_path, header=header))
    return all_rows


def export_trajectories_text(
    root: Path,
    *,
    format: str = "csv",
    level_id: str | None = None,
    task_id: str | None = None,
    outcome: str | None = "success",
) -> str:
    """Build trajectory export as a string (CSV or JSONL)."""
    fmt = format.lower()
    if fmt not in ("csv", "jsonl"):
        raise ValueError(f"unsupported format: {format!r}")
    rows = collect_trajectory_rows(
        root, level_id=level_id, task_id=task_id, outcome=outcome
    )
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
    level_id: str | None = None,
    task_id: str | None = None,
    outcome: str | None = "success",
) -> int:
    """Export trajectories with optional IL filters.

    Returns the number of entity-frame rows written. Default ``outcome=success``
    keeps abort/disconnect out of positive IL samples (V3b).
    """
    rows = collect_trajectory_rows(
        root, level_id=level_id, task_id=task_id, outcome=outcome
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as out_fp:
        if format.lower() == "jsonl":
            _write_jsonl(rows, out_fp)
        else:
            _write_csv(rows, out_fp)
    return len(rows)
