#!/usr/bin/env bash
# Export MineWorld Godot spike as a macOS .app (T3.4).
# Requires: Godot 4.7.x + matching export templates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/godot/spike"
OUT_DIR="$ROOT/dist/macos"
OUT_APP="$OUT_DIR/MineWorldSpike.app"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TEMPLATES_DIR="${HOME}/Library/Application Support/Godot/export_templates"
VERSION="$("$GODOT" --version 2>/dev/null | head -1 || true)"

echo "godot: $GODOT"
echo "version: ${VERSION:-unknown}"

if [[ ! -x "$GODOT" ]]; then
  echo "ERROR: Godot binary not found. Set GODOT=/path/to/Godot" >&2
  exit 1
fi

# 4.7.1.stable.official... → 4.7.1.stable
TPL_VER="$(echo "$VERSION" | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.stable.*/\1.stable/')"
if [[ -z "$TPL_VER" || "$TPL_VER" == "$VERSION" ]]; then
  TPL_VER="4.7.1.stable"
fi

if [[ ! -d "$TEMPLATES_DIR/$TPL_VER" ]]; then
  echo "ERROR: export templates missing at:" >&2
  echo "  $TEMPLATES_DIR/$TPL_VER" >&2
  echo "Install via Godot: Editor → Manage Export Templates → Download and Install" >&2
  echo "Or:" >&2
  echo "  curl -L -o /tmp/godot_tpl.tpz https://github.com/godotengine/godot/releases/download/${TPL_VER%-stable*}-stable/Godot_v${TPL_VER%.stable}-stable_export_templates.tpz" >&2
  echo "  unzip -d /tmp/godot_tpl /tmp/godot_tpl.tpz && mv /tmp/godot_tpl/templates \"$TEMPLATES_DIR/$TPL_VER\"" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$OUT_APP"

echo "exporting preset=macOS → $OUT_APP"
"$GODOT" --headless --path "$PROJECT" --export-release "macOS" "$OUT_APP"

if [[ ! -d "$OUT_APP" ]]; then
  echo "ERROR: export finished but $OUT_APP not found" >&2
  exit 1
fi

echo "OK: $OUT_APP"
echo "Run with Gateway up:"
echo "  open \"$OUT_APP\""
