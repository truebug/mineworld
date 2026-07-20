"""Serve Godot Web export with COOP/COEP headers (W1 local demo).

Also exposes local recording history (D5) and city-block regen (D9):
  GET  /api/recordings              → session list JSON
  GET  /api/recordings/<id>         → header.json
  GET  /api/recordings/<id>/frames  → frames.jsonl
  GET  /api/recordings/export.csv   → trajectory CSV (default outcome=success; ?level_id=&task_id=&outcome=)
  POST /api/recordings/reindex      → rebuild recordings/index.sqlite
  GET  /api/city-block              → current seed summary
  GET  /api/city-block/layout       → live block_layout.json (Godot Web dress)
  POST /api/city-block              → {"seed": N} regenerate contract+layout

Usage (from repo root, after `bash scripts/export_godot.sh web`):
  bash scripts/serve_web.sh restart          # 推荐：先杀旧 :8080 再启动
  bash scripts/serve_web.sh stop|start|status
  .venv/bin/python scripts/serve_web_demo.py # 直接跑（不杀旧进程）

Then open http://127.0.0.1:8080/ and keep Gateway on ws://127.0.0.1:8765.
History UI: http://127.0.0.1:8080/recordings.html (or in-game top-right **Recordings**).

Local API (same origin as the demo):

```text
GET  /api/recordings                 # session list
GET  /api/recordings/<id>            # header.json
GET  /api/recordings/<id>/frames     # frames.jsonl
GET  /api/recordings/export.csv      # trajectory CSV (?level_id=&task_id=&outcome=success|all)
POST /api/recordings/reindex         # rebuild index.sqlite
GET  /api/city-block                 # {seed, buildings, roads, ...}
GET  /api/city-block/layout          # Godot dress JSON
POST /api/city-block                 # body {"seed": 7} or {"seed": null} random
```

Sessions are read from `recordings/sessions/` (Gateway default record dir).
After POST city-block, reload the page (private room) so Gateway picks up the
new contract via mtime and Godot re-fetches layout.
"""

from __future__ import annotations

import argparse
import json
import functools
import random
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

REPO = Path(__file__).resolve().parents[1]
if str(REPO / "gateway") not in sys.path:
    sys.path.insert(0, str(REPO / "gateway"))
if str(REPO) not in sys.path:
    sys.path.insert(0, str(REPO))

from recording_store import DB_PATH, export_trajectories_text, list_sessions, rebuild_sqlite  # noqa: E402
from mw_platform.config import auth_enabled  # noqa: E402
from mw_platform.handlers import handle_platform_get, handle_platform_post, init_platform_data  # noqa: E402
LAYOUT_PATH = REPO / "godot" / "spike" / "assets" / "kaykit_city" / "block_layout.json"
CONTRACT_PATH = REPO / "examples" / "contracts" / "demo_city.json"


def _safe_session_id(raw: str) -> str | None:
    """Allow only simple session directory names (uuid-like)."""
    if not raw or len(raw) > 80:
        return None
    for ch in raw:
        if not (ch.isalnum() or ch in "-_"):
            return None
    return raw


def _city_block_summary() -> dict[str, Any]:
    """Read current layout/contract seed summary."""
    seed = None
    buildings = 0
    roads = 0
    bounds: dict[str, Any] = {}
    if LAYOUT_PATH.is_file():
        try:
            data = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
            seed = data.get("seed")
            buildings = len(data.get("buildings") or [])
            roads = len(data.get("roads") or [])
            bounds = data.get("bounds") or {}
        except (OSError, json.JSONDecodeError):
            pass
    if seed is None and CONTRACT_PATH.is_file():
        try:
            seed = json.loads(CONTRACT_PATH.read_text(encoding="utf-8")).get("seed")
        except (OSError, json.JSONDecodeError):
            pass
    return {
        "seed": seed,
        "buildings": buildings,
        "roads": roads,
        "bounds": bounds,
        "layout": str(LAYOUT_PATH.relative_to(REPO)),
        "contract": str(CONTRACT_PATH.relative_to(REPO)),
    }


def _regen_city_block(seed: int) -> dict[str, Any]:
    """Run gen_demo_city_block.generate_and_write(seed)."""
    scripts = REPO / "scripts"
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    import gen_demo_city_block  # noqa: WPS433 — local helper next to this script

    return gen_demo_city_block.generate_and_write(int(seed))


class CoopCoepHandler(SimpleHTTPRequestHandler):
    """Static file handler + local recording / city-block API."""

    recordings_root: Path = Path()

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def _send_json(self, payload: Any, status: int = 200) -> None:
        """Write a JSON response with CORS-friendly content-type."""
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_text_file(self, path: Path, content_type: str) -> None:
        """Stream a text file from disk."""
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_csv_attachment(self, data: bytes, filename: str = "trajectories.csv") -> None:
        """Stream CSV bytes as a download attachment."""
        self.send_response(200)
        self.send_header("Content-Type", "text/csv; charset=utf-8")
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _read_json_body(self) -> dict[str, Any] | None:
        """Parse a small JSON object body; None on empty/invalid."""
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 4096:
            return {}
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None
        if isinstance(data, dict):
            return data
        return None

    def _get_header(self, name: str) -> str | None:
        return self.headers.get(name)

    def _try_platform_get(self, path: str) -> bool:
        return handle_platform_get(
            path,
            send_json=self._send_json,
            get_header=self._get_header,
        )

    def _try_platform_post(self, path: str) -> bool:
        return handle_platform_post(
            path,
            send_json=self._send_json,
            read_body=self._read_json_body,
            get_header=self._get_header,
        )

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        if path.startswith("/api/platform/"):
            if self._try_platform_get(path):
                return
            self._send_json({"error": "not_found"}, 404)
            return

        if path == "/api/city-block":
            self._send_json(_city_block_summary())
            return
        if path == "/api/city-block/layout":
            if not LAYOUT_PATH.is_file():
                self._send_json({"error": "missing_layout"}, 404)
                return
            self._send_text_file(LAYOUT_PATH, "application/json; charset=utf-8")
            return

        if path == "/api/recordings":
            self._send_json({"sessions": list_sessions(self.recordings_root)})
            return

        if path == "/api/recordings/export.csv":
            qs = parse_qs(parsed.query)
            level_id = (qs.get("level_id") or [None])[0]
            task_id = (qs.get("task_id") or [None])[0]
            outcome = (qs.get("outcome") or ["success"])[0]
            csv_bytes = export_trajectories_text(
                self.recordings_root,
                format="csv",
                level_id=level_id,
                task_id=task_id,
                outcome=outcome,
            ).encode("utf-8")
            self._send_csv_attachment(csv_bytes)
            return

        if path.startswith("/api/recordings/"):
            parts = [p for p in path.split("/") if p]
            # api recordings <id> [frames]
            if len(parts) < 3:
                self._send_json({"error": "not_found"}, 404)
                return
            sid = _safe_session_id(parts[2])
            if sid is None:
                self._send_json({"error": "bad_session_id"}, 400)
                return
            session_dir = (self.recordings_root / sid).resolve()
            try:
                session_dir.relative_to(self.recordings_root.resolve())
            except ValueError:
                self._send_json({"error": "bad_session_id"}, 400)
                return
            if not session_dir.is_dir():
                self._send_json({"error": "not_found"}, 404)
                return
            if len(parts) == 3:
                header = session_dir / "header.json"
                if not header.is_file():
                    self._send_json({"error": "not_found"}, 404)
                    return
                self._send_text_file(header, "application/json; charset=utf-8")
                return
            if len(parts) == 4 and parts[3] == "frames":
                frames = session_dir / "frames.jsonl"
                if not frames.is_file():
                    self._send_json({"error": "not_found"}, 404)
                    return
                self._send_text_file(frames, "application/x-ndjson; charset=utf-8")
                return
            self._send_json({"error": "not_found"}, 404)
            return

        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path.startswith("/api/platform/"):
            if self._try_platform_post(path):
                return
            self._send_json({"error": "not_found"}, 404)
            return
        if path == "/api/recordings/reindex":
            count = rebuild_sqlite(self.recordings_root, DB_PATH)
            self._send_json({"ok": True, "count": count})
            return
        if path != "/api/city-block":
            self._send_json({"error": "not_found"}, 404)
            return
        body = self._read_json_body()
        if body is None:
            self._send_json({"error": "bad_json"}, 400)
            return
        seed_raw = body.get("seed", None)
        if seed_raw is None:
            seed = random.randint(0, 999_999)
        else:
            try:
                seed = int(seed_raw)
            except (TypeError, ValueError):
                self._send_json({"error": "bad_seed"}, 400)
                return
        try:
            summary = _regen_city_block(seed)
        except Exception as exc:  # noqa: BLE001 — surface to browser
            self._send_json({"error": "regen_failed", "message": str(exc)}, 500)
            return
        summary["ok"] = True
        summary["hint"] = "reload page (private room) so Gateway + dress pick up the new seed"
        self._send_json(summary)


def main() -> None:
    repo = REPO
    parser = argparse.ArgumentParser(description="Serve MineWorld Web export with COOP/COEP")
    parser.add_argument(
        "--dir",
        type=Path,
        default=repo / "dist" / "web",
        help="Directory containing index.html",
    )
    parser.add_argument(
        "--recordings",
        type=Path,
        default=repo / "recordings" / "sessions",
        help="Session recording root (header.json + frames.jsonl)",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    root = args.dir.resolve()
    if not (root / "index.html").exists():
        raise SystemExit(
            f"missing {root / 'index.html'}; run: bash scripts/export_godot.sh web"
        )

    recordings_root = args.recordings.resolve()
    recordings_root.mkdir(parents=True, exist_ok=True)

    init_platform_data()

    # Portal pages + history UI next to export.
    portal_src_dir = repo / "godot" / "spike" / "web" / "portal"
    if portal_src_dir.is_dir():
        portal_dst = root / "portal"
        portal_dst.mkdir(parents=True, exist_ok=True)
        for src in portal_src_dir.glob("*.html"):
            (portal_dst / src.name).write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

    src_ui = repo / "godot" / "spike" / "web" / "recordings.html"
    if src_ui.is_file():
        (root / "recordings.html").write_text(src_ui.read_text(encoding="utf-8"), encoding="utf-8")

    handler = functools.partial(CoopCoepHandler, directory=str(root))
    CoopCoepHandler.recordings_root = recordings_root
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"serving {root}")
    print(f"recordings {recordings_root}")
    print(f"open http://{args.host}:{args.port}/")
    print(f"portal http://{args.host}:{args.port}/portal/login.html")
    print(f"history http://{args.host}:{args.port}/recordings.html")
    print(f"platform auth={'on' if auth_enabled() else 'off'} · demo login demo/demo")
    print("headers: COOP=same-origin COEP=require-corp CORP=same-origin")
    print("gateway expected at ws://127.0.0.1:8765 (override via window.MINEWORLD_GATEWAY)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutdown")


if __name__ == "__main__":
    main()
