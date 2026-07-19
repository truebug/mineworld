#!/usr/bin/env bash
# Export MineWorld Godot spike (T3.4 macOS / W1 Web).
# Usage:
#   bash scripts/export_godot.sh           # default: web
#   bash scripts/export_godot.sh web
#   bash scripts/export_godot.sh macos
# Requires: Godot 4.7.x + matching export templates (incl. Web for web target).
set -euo pipefail

TARGET="${1:-web}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/godot/spike"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TEMPLATES_DIR="${HOME}/Library/Application Support/Godot/export_templates"
VERSION="$("$GODOT" --version 2>/dev/null | head -1 || true)"

echo "godot: $GODOT"
echo "version: ${VERSION:-unknown}"
echo "target: $TARGET"

if [[ ! -x "$GODOT" ]]; then
  echo "ERROR: Godot binary not found. Set GODOT=/path/to/Godot" >&2
  exit 1
fi

TPL_VER="$(echo "$VERSION" | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.stable.*/\1.stable/')"
if [[ -z "$TPL_VER" || "$TPL_VER" == "$VERSION" ]]; then
  TPL_VER="4.7.1.stable"
fi

if [[ ! -d "$TEMPLATES_DIR/$TPL_VER" ]]; then
  echo "ERROR: export templates missing at:" >&2
  echo "  $TEMPLATES_DIR/$TPL_VER" >&2
  echo "Install via Godot: Editor → Manage Export Templates → Download and Install" >&2
  echo "For Web target, ensure the Web template is selected." >&2
  exit 1
fi

case "$TARGET" in
  web|Web)
    PRESET="Web"
    OUT_DIR="$ROOT/dist/web"
    OUT_FILE="$OUT_DIR/index.html"
    mkdir -p "$OUT_DIR"
    echo "exporting preset=$PRESET → $OUT_FILE"
    "$GODOT" --headless --path "$PROJECT" --export-release "$PRESET" "$OUT_FILE"
    if [[ ! -f "$OUT_FILE" ]]; then
      echo "ERROR: export finished but $OUT_FILE not found" >&2
      exit 1
    fi
    # Main-thread key bridge (required: multi-thread workers cannot bind document).
    cp "$PROJECT/web/mw_key_bridge.js" "$OUT_DIR/mw_key_bridge.js"
    if ! grep -q "mw_key_bridge.js" "$OUT_FILE"; then
      # Fallback if head_include was stripped: inject before </head>
      sed -i.bak 's#</head>#<script src="mw_key_bridge.js"></script></head>#' "$OUT_FILE"
      rm -f "$OUT_FILE.bak"
    fi
    echo "OK: $OUT_DIR (single-thread Web + mw_key_bridge.js)"
    echo "Serve:"
    echo "  .venv/bin/python scripts/serve_web_demo.py"
    echo "Gateway:"
    echo "  .venv/bin/python gateway/echo_server.py --host 127.0.0.1"
    echo "Expect console: [MW] key bridge installed on document"
    ;;
  macos|macOS|osx)
    PRESET="macOS"
    OUT_DIR="$ROOT/dist/macos"
    OUT_APP="$OUT_DIR/MineWorldSpike.app"
    mkdir -p "$OUT_DIR"
    rm -rf "$OUT_APP"
    echo "exporting preset=$PRESET → $OUT_APP"
    "$GODOT" --headless --path "$PROJECT" --export-release "$PRESET" "$OUT_APP"
    if [[ ! -d "$OUT_APP" ]]; then
      echo "ERROR: export finished but $OUT_APP not found" >&2
      exit 1
    fi
    echo "OK: $OUT_APP"
    echo "Run with Gateway up: open \"$OUT_APP\""
    ;;
  *)
    echo "ERROR: unknown target '$TARGET' (use: web | macos)" >&2
    exit 1
    ;;
esac
