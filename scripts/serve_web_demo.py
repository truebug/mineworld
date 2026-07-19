"""Serve Godot Web export with COOP/COEP headers (W1 local demo).

Also exposes local recording history (D5):
  GET /api/recordings              → session list JSON
  GET /api/recordings/<id>         → header.json
  GET /api/recordings/<id>/frames  → frames.jsonl

Usage (from repo root, after `bash scripts/export_godot.sh web`):
  bash scripts/serve_web.sh restart          # 推荐：先杀旧 :8080 再启动
  bash scripts/serve_web.sh stop|start|status
  .venv/bin/python scripts/serve_web_demo.py # 直接跑（不杀旧进程）

Then open http://127.0.0.1:8080/ and keep Gateway on ws://127.0.0.1:8765.
History UI: http://127.0.0.1:8080/recordings.html (or in-game top-right **Recordings**).

Local API (same origin as the demo):

```text
GET /api/recordings                 # session list
GET /api/recordings/<id>            # header.json
GET /api/recordings/<id>/frames     # frames.jsonl
```

Sessions are read from `recordings/sessions/` (Gateway default record dir).
"""

from __future__ import annotations

import argparse
import json
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


def _safe_session_id(raw: str) -> str | None:
    """Allow only simple session directory names (uuid-like)."""
    if not raw or len(raw) > 80:
        return None
    for ch in raw:
        if not (ch.isalnum() or ch in "-_"):
            return None
    return raw


def list_sessions(root: Path) -> list[dict[str, Any]]:
    """Scan recordings/sessions/* and return summary dicts (newest first)."""
    if not root.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for child in root.iterdir():
        if not child.is_dir():
            continue
        header_path = child / "header.json"
        frames_path = child / "frames.jsonl"
        if not header_path.is_file():
            continue
        try:
            header = json.loads(header_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        stats = header.get("stats") or {}
        out.append(
            {
                "session_id": header.get("session_id") or child.name,
                "level_id": header.get("level_id"),
                "outcome": header.get("outcome"),
                "started_at": header.get("started_at"),
                "ended_at": header.get("ended_at"),
                "duration_sim_s": stats.get("duration_sim_s"),
                "num_frames": stats.get("num_frames"),
                "features": header.get("features") or [],
                "has_frames": frames_path.is_file(),
            }
        )
    out.sort(key=lambda s: str(s.get("started_at") or ""), reverse=True)
    return out


class CoopCoepHandler(SimpleHTTPRequestHandler):
    """Static file handler + local recording API (D5)."""

    recordings_root: Path = Path()

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
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

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)

        if path == "/api/recordings":
            self._send_json({"sessions": list_sessions(self.recordings_root)})
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


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
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

    # Copy history UI next to the export if present in repo.
    src_ui = repo / "godot" / "spike" / "web" / "recordings.html"
    if src_ui.is_file():
        (root / "recordings.html").write_text(src_ui.read_text(encoding="utf-8"), encoding="utf-8")

    handler = functools.partial(CoopCoepHandler, directory=str(root))
    CoopCoepHandler.recordings_root = recordings_root
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"serving {root}")
    print(f"recordings {recordings_root}")
    print(f"open http://{args.host}:{args.port}/")
    print(f"history http://{args.host}:{args.port}/recordings.html")
    print("headers: COOP=same-origin COEP=require-corp")
    print("gateway expected at ws://127.0.0.1:8765 (override via window.MINEWORLD_GATEWAY)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutdown")


if __name__ == "__main__":
    main()
