"""PL2: Gateway admin HTTP — rooms snapshot + level disable/enable."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ADMIN_PORT = 8777  # avoid colliding with a local 8770 gateway


def _wait_port(host: str, port: int, *, timeout: float = 15.0) -> bool:
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


def _req(url: str, *, key: str, method: str = "GET", body: dict | None = None) -> dict:
    """JSON request with X-Admin-Key."""
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "X-Admin-Key": key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    """Start gateway with admin HTTP, assert rooms/contracts/level toggle."""
    host = "127.0.0.1"
    ws_port = 8767
    key = "dev-admin-smoke"
    env = os.environ.copy()
    env["MW_GATEWAY_ADMIN_KEY"] = key

    try:
        subprocess.run(
            [
                "bash",
                "-lc",
                f"lsof -tiTCP:{ws_port} -sTCP:LISTEN | xargs kill 2>/dev/null || true; "
                f"lsof -tiTCP:{ADMIN_PORT} -sTCP:LISTEN | xargs kill 2>/dev/null || true",
            ],
            check=False,
        )
        time.sleep(0.2)
    except OSError:
        pass

    gw = subprocess.Popen(
        [
            str(REPO / ".venv" / "bin" / "python"),
            str(REPO / "gateway" / "echo_server.py"),
            "--physics",
            "fake",
            "--host",
            host,
            "--port",
            str(ws_port),
            "--admin-host",
            host,
            "--admin-port",
            str(ADMIN_PORT),
        ],
        cwd=str(REPO),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    base = f"http://{host}:{ADMIN_PORT}"
    try:
        if not _wait_port(host, ADMIN_PORT):
            err = (gw.stderr.read() if gw.stderr else b"").decode("utf-8", errors="replace")
            print(f"FAIL: admin HTTP not up\n{err}", file=sys.stderr)
            return 1

        rooms = _req(f"{base}/admin/rooms", key=key)
        if not rooms.get("ok") or "rooms" not in rooms:
            print(f"FAIL: rooms={rooms}", file=sys.stderr)
            return 1

        contracts = _req(f"{base}/admin/contracts", key=key)
        if not contracts.get("ok"):
            print(f"FAIL: contracts={contracts}", file=sys.stderr)
            return 1

        dis = _req(
            f"{base}/admin/levels/disable",
            key=key,
            method="POST",
            body={"level_id": "demo_workshop"},
        )
        if not dis.get("ok") or "demo_workshop" not in dis.get("disabled_levels", []):
            print(f"FAIL: disable={dis}", file=sys.stderr)
            return 1

        en = _req(
            f"{base}/admin/levels/enable",
            key=key,
            method="POST",
            body={"level_id": "demo_workshop"},
        )
        if not en.get("ok") or "demo_workshop" in en.get("disabled_levels", []):
            print(f"FAIL: enable={en}", file=sys.stderr)
            return 1

        try:
            _req(f"{base}/admin/rooms", key="wrong")
            print("FAIL: expected 403 for bad key", file=sys.stderr)
            return 1
        except urllib.error.HTTPError as exc:
            if exc.code != 403:
                print(f"FAIL: expected 403 got {exc.code}", file=sys.stderr)
                return 1

        print("admin-ops OK rooms/contracts/level-toggle")
        return 0
    finally:
        gw.send_signal(signal.SIGTERM)
        try:
            gw.wait(timeout=5)
        except subprocess.TimeoutExpired:
            gw.kill()


if __name__ == "__main__":
    raise SystemExit(main())
