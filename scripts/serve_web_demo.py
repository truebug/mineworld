"""Serve Godot Web export with COOP/COEP headers (W1 local demo).

Godot 4 threaded Web builds need:
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp

Usage (from repo root, after `bash scripts/export_godot.sh web`):
  .venv/bin/python scripts/serve_web_demo.py
  .venv/bin/python scripts/serve_web_demo.py --port 8080 --dir dist/web

Then open http://127.0.0.1:8080/ and keep Gateway on ws://127.0.0.1:8765.
"""

from __future__ import annotations

import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class CoopCoepHandler(SimpleHTTPRequestHandler):
    """Static file handler that injects isolation headers for SharedArrayBuffer."""

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve MineWorld Web export with COOP/COEP")
    parser.add_argument(
        "--dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "dist" / "web",
        help="Directory containing index.html",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    root = args.dir.resolve()
    if not (root / "index.html").exists():
        raise SystemExit(
            f"missing {root / 'index.html'}; run: bash scripts/export_godot.sh web"
        )

    handler = functools.partial(CoopCoepHandler, directory=str(root))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"serving {root}")
    print(f"open http://{args.host}:{args.port}/")
    print("headers: COOP=same-origin COEP=require-corp")
    print("gateway expected at ws://127.0.0.1:8765 (override via window.MINEWORLD_GATEWAY)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutdown")


if __name__ == "__main__":
    main()
