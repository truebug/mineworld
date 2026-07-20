#!/usr/bin/env python3
"""Standalone MineWorld platform API (Phase A · PL1).

Usage (repo root):
  .venv/bin/python mw_platform/api_server.py

Env:
  MW_PLATFORM_DB_URL=sqlite:///path/to/platform.sqlite  (default under mw_platform/data/)
  MW_PLATFORM_HOST=127.0.0.1
  MW_PLATFORM_PORT=8090
  MW_PLATFORM_ADMIN_KEY=dev-admin   # optional; enables admin routes
  MW_PLATFORM_AUTH=1                # web gate uses same store via /api/platform on :8080

When integrated with scripts/serve_web_demo.py, routes are also served on the
game port (same-origin). This process is for health checks and split deploy.
"""

from __future__ import annotations

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

REPO = Path(__file__).resolve().parents[1]
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

from mw_platform.config import bind_host, bind_port  # noqa: E402
from mw_platform.handlers import (  # noqa: E402
    handle_platform_get,
    handle_platform_post,
    init_platform_data,
)


class PlatformHandler(BaseHTTPRequestHandler):
    """Minimal JSON API server."""

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    def _send_json(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict[str, Any] | None:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 8192:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        return data if isinstance(data, dict) else None

    def _header(self, name: str) -> str | None:
        return self.headers.get(name)

    def do_GET(self) -> None:
        path = unquote(urlparse(self.path).path)
        if handle_platform_get(
            path,
            send_json=self._send_json,
            get_header=self._header,
        ):
            return
        self._send_json({"error": "not_found"}, 404)

    def do_POST(self) -> None:
        path = unquote(urlparse(self.path).path)
        if handle_platform_post(
            path,
            send_json=self._send_json,
            read_body=self._read_json_body,
            get_header=self._header,
        ):
            return
        self._send_json({"error": "not_found"}, 404)


def main() -> None:
    init_platform_data()
    host, port = bind_host(), bind_port()
    server = ThreadingHTTPServer((host, port), PlatformHandler)
    print(f"mw_platform API http://{host}:{port}/")
    print(f"  GET  /api/platform/health")
    print(f"  POST /api/platform/login")
    print(f"  GET  /api/platform/me  (Bearer token)")
    print("demo login: player_id=demo password=demo")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutdown")


if __name__ == "__main__":
    main()
