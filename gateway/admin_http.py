"""Minimal Gateway admin HTTP (PL2): rooms snapshot + contract/level toggles."""

from __future__ import annotations

import json
import logging
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import TYPE_CHECKING, Any
from urllib.parse import urlparse

if TYPE_CHECKING:
    from echo_server import EchoGateway

LOG = logging.getLogger("mineworld.admin_http")


def _admin_key() -> str:
    return (
        os.environ.get("MW_PLATFORM_ADMIN_KEY")
        or os.environ.get("MW_GATEWAY_ADMIN_KEY")
        or "dev-admin"
    )


def start_admin_http(gateway: EchoGateway, *, host: str, port: int) -> ThreadingHTTPServer | None:
    """Serve PL2 admin API in a daemon thread. Returns server or None if port<=0."""
    if port <= 0:
        return None

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            LOG.debug("admin_http " + fmt, *args)

        def _send(self, code: int, body: dict[str, Any]) -> None:
            raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def _authorized(self) -> bool:
            key = self.headers.get("X-Admin-Key") or self.headers.get("x-admin-key") or ""
            expected = _admin_key()
            return bool(expected and key == expected)

        def do_GET(self) -> None:  # noqa: N802
            path = urlparse(self.path).path
            if not self._authorized():
                self._send(403, {"error": "forbidden"})
                return
            if path in ("/admin/rooms", "/rooms"):
                self._send(200, {"ok": True, "rooms": gateway.rooms_snapshot()})
                return
            if path in ("/admin/contracts", "/contracts"):
                self._send(200, {"ok": True, **gateway.contracts_snapshot()})
                return
            if path in ("/admin/status", "/status"):
                self._send(200, {"ok": True, **gateway.admin_status()})
                return
            self._send(404, {"error": "not_found"})

        def do_POST(self) -> None:  # noqa: N802
            path = urlparse(self.path).path
            if not self._authorized():
                self._send(403, {"error": "forbidden"})
                return
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length > 0 else b"{}"
            try:
                body = json.loads(raw.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                self._send(400, {"error": "bad_json"})
                return
            if not isinstance(body, dict):
                self._send(400, {"error": "bad_json"})
                return
            level_id = str(body.get("level_id", "")).strip()
            if path in ("/admin/levels/disable", "/levels/disable"):
                if not level_id:
                    self._send(400, {"error": "missing_level_id"})
                    return
                gateway.disable_level(level_id)
                self._send(200, {"ok": True, **gateway.contracts_snapshot()})
                return
            if path in ("/admin/levels/enable", "/levels/enable"):
                if not level_id:
                    self._send(400, {"error": "missing_level_id"})
                    return
                gateway.enable_level(level_id)
                self._send(200, {"ok": True, **gateway.contracts_snapshot()})
                return
            self._send(404, {"error": "not_found"})

    server = ThreadingHTTPServer((host, port), Handler)
    thread = threading.Thread(target=server.serve_forever, name="mw-admin-http", daemon=True)
    thread.start()
    LOG.info("admin HTTP on http://%s:%s/admin/rooms (X-Admin-Key)", host, port)
    return server
