"""V-IL: record a workshop stow-crate success, then export-filter assert ≥1 row."""

from __future__ import annotations

import argparse
import csv
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "gateway") not in sys.path:
    sys.path.insert(0, str(REPO / "gateway"))
if str(REPO / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO / "scripts"))

from recording_store import export_trajectories  # noqa: E402
from stow_crate_smoke import stow_crate  # noqa: E402
import asyncio  # noqa: E402


def _wait_port(host: str, port: int, *, timeout: float = 20.0) -> bool:
    """Return True when TCP port accepts connections."""
    import socket

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.1)
    return False


def main() -> int:
    """Start mujoco gateway with recording, stow crate, export success rows."""
    parser = argparse.ArgumentParser(description="V-IL recorded stow + export smoke")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--seconds", type=float, default=30.0)
    parser.add_argument(
        "--record-dir",
        type=Path,
        default=REPO / "recordings" / "il_smoke_sessions",
        help="Temporary session root for this smoke (gitignored parent ok)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO / "recordings" / "exports" / "il_smoke.csv",
        help="Export CSV path written by this smoke",
    )
    args = parser.parse_args()

    record_dir = args.record_dir.resolve()
    record_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.out.resolve()

    # Free port if a leftover gateway is listening.
    try:
        subprocess.run(
            ["bash", "-lc", f"lsof -tiTCP:{args.port} -sTCP:LISTEN | xargs kill 2>/dev/null || true"],
            check=False,
        )
        time.sleep(0.3)
    except OSError:
        pass

    env = os.environ.copy()
    gw = subprocess.Popen(
        [
            str(REPO / ".venv" / "bin" / "python"),
            str(REPO / "gateway" / "echo_server.py"),
            "--physics",
            "mujoco",
            "--host",
            args.host,
            "--port",
            str(args.port),
            "--record-dir",
            str(record_dir),
            "--contract",
            str(REPO / "examples" / "contracts" / "demo_workshop.json"),
        ],
        cwd=str(REPO),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    try:
        if not _wait_port(args.host, args.port):
            err = (gw.stderr.read() if gw.stderr else b"").decode("utf-8", errors="replace")
            print(f"FAIL: gateway did not listen on {args.host}:{args.port}\n{err}", file=sys.stderr)
            return 1

        url = f"ws://{args.host}:{args.port}"
        stow_rc = asyncio.run(stow_crate(url, seconds=args.seconds))
        if stow_rc != 0:
            print("FAIL: stow_crate smoke failed", file=sys.stderr)
            return stow_rc

        # Allow recorder close() on WS disconnect to flush header outcome=success.
        time.sleep(0.8)

        rows = export_trajectories(
            record_dir,
            out_path,
            format="csv",
            level_id="demo_workshop",
            task_id="obj_stow_crate",
            outcome="success",
        )
        if rows < 1:
            print(
                f"FAIL: expected ≥1 export row for demo_workshop/success, got {rows}",
                file=sys.stderr,
            )
            return 1

        with out_path.open(encoding="utf-8", newline="") as fp:
            reader = csv.DictReader(fp)
            first = next(reader, None)
        if first is None:
            print("FAIL: export CSV empty after row count>0", file=sys.stderr)
            return 1
        if first.get("level_id") != "demo_workshop" or first.get("outcome") != "success":
            print(f"FAIL: bad export meta {first}", file=sys.stderr)
            return 1
        if not first.get("joints"):
            print("FAIL: expected joints column on mech row", file=sys.stderr)
            return 1

        print(
            f"V-IL OK rows={rows} session={first.get('session_id')} "
            f"out={out_path}"
        )
        return 0
    finally:
        if gw.poll() is None:
            gw.send_signal(signal.SIGTERM)
            try:
                gw.wait(timeout=5)
            except subprocess.TimeoutExpired:
                gw.kill()


if __name__ == "__main__":
    raise SystemExit(main())
