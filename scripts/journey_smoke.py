#!/usr/bin/env python3
"""C3: product journey smoke — login → join+profile → success points → me/lb.

Uses demo_city open-loop finish (mech reach) because workshop push is unreliable
after P1a shrunk prop_crate. Still validates C1 profile + C2 points/score post.
Requires MuJoCo.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import websockets

REPO = Path(__file__).resolve().parents[1]


def _wait_port(host: str, port: int, *, timeout: float = 25.0) -> bool:
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


def _http_json(
    method: str,
    url: str,
    *,
    body: dict | None = None,
    headers: dict[str, str] | None = None,
    timeout_s: float = 5.0,
) -> dict:
    """POST/GET JSON; raise on non-2xx."""
    data = None if body is None else json.dumps(body).encode("utf-8")
    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else {}


def _free_port() -> int:
    """Bind ephemeral port and return it."""
    import socket

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


async def _send_vel(ws, session_id: str, vx: float) -> None:
    """Send chassis velocity cmd."""
    await ws.send(
        json.dumps(
            {
                "type": "cmd",
                "session_id": session_id,
                "payload": {
                    "entity_id": "mech_player",
                    "control_mode": "velocity",
                    "vx": vx,
                    "vy": 0.0,
                    "yaw_rate": 0.0,
                },
            }
        )
    )


async def city_success_with_profile(
    url: str,
    *,
    player_id: str,
    nickname: str,
    seconds: float,
) -> tuple[str, int]:
    """Join demo_city with profile; drive east until objective_complete; return sid, points."""
    async with websockets.connect(url) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert hello.get("type") == "hello", hello
        features = (hello.get("payload") or {}).get("features", [])
        if "mujoco" not in features:
            raise RuntimeError("need --physics mujoco")
        sid = str(hello["session_id"])
        await ws.send(
            json.dumps(
                {
                    "type": "join",
                    "session_id": sid,
                    "payload": {
                        "level_id": "demo_city",
                        "player_name": nickname,
                        "extensions": {
                            "mw": {
                                "profile": {
                                    "id": player_id,
                                    "nickname": nickname,
                                    "accent": "#4aa3ff",
                                }
                            }
                        },
                    },
                }
            )
        )
        scene = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
        assert scene.get("type") == "scene", scene

        await ws.send(
            json.dumps(
                {
                    "type": "cmd",
                    "session_id": sid,
                    "payload": {"action": "take_control", "entity_id": "mech_player"},
                }
            )
        )

        deadline = asyncio.get_event_loop().time() + seconds
        last_cmd = 0.0
        while asyncio.get_event_loop().time() < deadline:
            now = asyncio.get_event_loop().time()
            if now - last_cmd >= 0.05:
                await _send_vel(ws, sid, 1.0)
                last_cmd = now
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            if msg.get("type") != "event":
                continue
            payload = msg.get("payload") or {}
            if payload.get("event_type") != "objective_complete":
                continue
            detail = payload.get("detail") or {}
            points = int(detail.get("points") or payload.get("points") or 0)
            return sid, points

        raise RuntimeError("expected objective_complete with points")


def main() -> int:
    """Spawn platform + mujoco gateway; assert score lands on demo player."""
    parser = argparse.ArgumentParser(description="C3 product journey smoke")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--ws-port", type=int, default=0, help="0 = ephemeral")
    parser.add_argument("--http-port", type=int, default=0, help="0 = ephemeral")
    parser.add_argument("--seconds", type=float, default=70.0)
    parser.add_argument("--player-id", default="demo")
    parser.add_argument("--password", default="demo")
    args = parser.parse_args()

    http_port = args.http_port or _free_port()
    ws_port = args.ws_port or _free_port()
    tmp = tempfile.mkdtemp(prefix="mw_journey_")
    db_path = Path(tmp) / "platform.sqlite"
    record_dir = Path(tmp) / "sessions"
    record_dir.mkdir(parents=True, exist_ok=True)

    py = str(REPO / ".venv" / "bin" / "python")
    if not Path(py).is_file():
        py = sys.executable

    http_env = os.environ.copy()
    http_env["MW_PLATFORM_DB_URL"] = f"sqlite:///{db_path}"
    http_env["MW_PLATFORM_AUTH"] = "1"
    http_env["MW_PLATFORM_HOST"] = args.host
    http_env["MW_PLATFORM_PORT"] = str(http_port)
    http_env["MW_PLATFORM_ADMIN_KEY"] = (
        os.environ.get("MW_PLATFORM_ADMIN_KEY") or "dev-admin"
    )
    http_env["MW_PLATFORM_GATEWAY_KEY"] = (
        os.environ.get("MW_PLATFORM_GATEWAY_KEY")
        or "mineworld-gateway-dev"
    )

    http_proc = subprocess.Popen(
        [py, str(REPO / "mw_platform" / "api_server.py")],
        cwd=str(REPO),
        env=http_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    gw_env = os.environ.copy()
    gw_env["MW_PLATFORM_SCORE_URL"] = (
        f"http://{args.host}:{http_port}/api/platform/scores"
    )
    gw_env["MW_PLATFORM_GATEWAY_KEY"] = http_env["MW_PLATFORM_GATEWAY_KEY"]

    gw = subprocess.Popen(
        [
            py,
            str(REPO / "gateway" / "echo_server.py"),
            "--physics",
            "mujoco",
            "--host",
            args.host,
            "--port",
            str(ws_port),
            "--record-dir",
            str(record_dir),
            "--contract",
            str(REPO / "examples" / "contracts" / "demo_city.json"),
        ],
        cwd=str(REPO),
        env=gw_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )

    try:
        if not _wait_port(args.host, http_port):
            err = (http_proc.stderr.read() if http_proc.stderr else b"").decode(
                "utf-8", errors="replace"
            )
            print(f"FAIL: platform HTTP not on :{http_port}\n{err}", file=sys.stderr)
            return 1
        if not _wait_port(args.host, ws_port):
            err = (gw.stderr.read() if gw.stderr else b"").decode(
                "utf-8", errors="replace"
            )
            print(f"FAIL: gateway not on :{ws_port}\n{err}", file=sys.stderr)
            return 1

        base = f"http://{args.host}:{http_port}"
        try:
            login = _http_json(
                "POST",
                f"{base}/api/platform/login",
                body={"player_id": args.player_id, "password": args.password},
            )
        except urllib.error.HTTPError as exc:
            print(f"FAIL: login HTTP {exc.code}", file=sys.stderr)
            return 1
        token = str(login.get("token") or "")
        if not token:
            print(f"FAIL: no token in login {login}", file=sys.stderr)
            return 1

        me_before = _http_json(
            "GET",
            f"{base}/api/platform/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        stats_b = me_before.get("stats") if isinstance(me_before.get("stats"), dict) else {}
        pts_before = int(stats_b.get("total_points") or 0)

        ws_url = f"ws://{args.host}:{ws_port}"
        try:
            session_id, points = asyncio.run(
                city_success_with_profile(
                    ws_url,
                    player_id=args.player_id,
                    nickname="Journey Pilot",
                    seconds=args.seconds,
                )
            )
        except Exception as exc:  # noqa: BLE001 — surface smoke failure
            print(f"FAIL: city journey: {exc}", file=sys.stderr)
            return 1

        if points < 1:
            print(f"FAIL: expected points in objective_complete, got {points}", file=sys.stderr)
            return 1

        time.sleep(1.0)

        me_after = _http_json(
            "GET",
            f"{base}/api/platform/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        stats_a = me_after.get("stats") if isinstance(me_after.get("stats"), dict) else {}
        pts_after = int(stats_a.get("total_points") or 0)
        scores = me_after.get("scores") or []
        found = any(
            isinstance(row, dict) and str(row.get("session_id")) == session_id
            for row in scores
        )
        if not found and pts_after < pts_before + 1:
            print(
                f"FAIL: score not on me (before={pts_before} after={pts_after} "
                f"event_pts={points} session={session_id}) body={me_after}",
                file=sys.stderr,
            )
            return 1

        lb = _http_json("GET", f"{base}/api/platform/leaderboard")
        entries = lb.get("entries") if isinstance(lb, dict) else []
        if not any(
            isinstance(e, dict) and str(e.get("player_id")) == args.player_id
            for e in entries
        ):
            print(f"FAIL: player not on leaderboard {lb}", file=sys.stderr)
            return 1

        headers = list(record_dir.glob("*/header.json"))
        if headers:
            hdr = json.loads(headers[-1].read_text(encoding="utf-8"))
            pid = str(hdr.get("player_id") or "")
            if pid != args.player_id:
                print(f"FAIL: header player_id={pid!r} want={args.player_id}", file=sys.stderr)
                return 1

        print(
            f"journey smoke OK session={session_id} points={points} "
            f"me={pts_before}->{pts_after} http=:{http_port} ws=:{ws_port}"
        )
        return 0
    finally:
        for proc in (gw, http_proc):
            if proc.poll() is None:
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()


if __name__ == "__main__":
    raise SystemExit(main())
