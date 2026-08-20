#!/usr/bin/env bash
# Deploy MineWorld to playground (binjietk CVM).
# Usage: bash scripts/deploy_playground.sh
# Steps: export → verify pck → inject build/gateway → rsync → brand+restart → curl check
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REMOTE="${MW_REMOTE:-binjietk:/opt/mineworld/}"
SSH_HOST="${MW_SSH:-binjietk}"
GATEWAY_URL="wss://playground.dev.databall.tech/ws"
SITE_URL="https://playground.dev.databall.tech/"

echo "== 1/6 export web =="
bash scripts/export_godot.sh web
# P0: never ship retired DOM pad (rsync has no --delete for orphans).
rm -f dist/web/mw_touch_pad.js

echo "== 1.5/6 gdscript lint =="
.venv/bin/python scripts/gdscript_lint.py || { echo "ERROR: gdscript lint failed" >&2; exit 1; }

echo "== 1.6/6 scene boot check (compile gate) =="
bash scripts/check_scenes_boot.sh || { echo "ERROR: scene boot check failed — aborting deploy" >&2; exit 1; }

echo "== 2/6 verify pck contents =="
PCK="dist/web/index.pck"
[[ -f "$PCK" ]] || { echo "ERROR: $PCK missing" >&2; exit 1; }
PCK_STRINGS="$(mktemp)"
strings "$PCK" > "$PCK_STRINGS"
for token in race_layout FallbackGrass; do
  if ! grep -q "$token" "$PCK_STRINGS"; then
    echo "ERROR: pck missing '$token' — check include_filter / scripts" >&2
    exit 1
  fi
done
# race_dress parse-error regression guard
if grep -q "var bi :=" "$PCK_STRINGS"; then
  echo "ERROR: pck still has untyped 'bi' (parse error)" >&2
  exit 1
fi
rm -f "$PCK_STRINGS"
echo "pck OK ($(du -h "$PCK" | cut -f1))"

echo "== 3/6 inject build + gateway =="
MW_BUILD="$(date +%Y%m%d-%H%M%S)"
python3 - "$MW_BUILD" "$GATEWAY_URL" << 'PY'
import re, sys
build, gw = sys.argv[1], sys.argv[2]
p = 'dist/web/index.html'
s = open(p).read()
for var, val in [("MW_BUILD", build), ("MINEWORLD_GATEWAY", gw)]:
    pat = rf'window\.{var}\s*=\s*"[^"]*"'
    inj = f'window.{var}="{val}"'
    s = re.sub(pat, inj, s) if re.search(pat, s) else s.replace('<head>', f'<head>\n<script>{inj};</script>', 1)
# Cache-bust the immutable pck URL: index.pck?v=<build> so browsers/CDN
# that hold a 30-day immutable cache still fetch the new game content.
s = re.sub(r'"index\.pck"', f'"index.pck?v={build}"', s)
open(p, 'w').write(s)
print(f"MW_BUILD={build}")
PY

echo "== 4/6 rsync =="
# No --delete: shared /opt/mineworld hosts dist/xr + dist/arm + dist/g1 from other repos.
# Whole-tree --delete previously wiped those (see docs/ops.local.md §5.1–5.2).
# Neighbour routes: /xr/ (mine-world-xr), /arm/ (mine-world-arm), /g1/ (g1claw) — do not reclaim.
rsync -az \
  --exclude '.venv/' --exclude '.git/' --exclude 'recordings/' \
  --exclude 'mw_platform/data/*.sqlite' --exclude 'godot/spike/.godot/' \
  --exclude 'scripts/*.local.py' --exclude 'docs/*.local.md' \
  ./ "$REMOTE"
rsync -az scripts/inject_site_branding.local.py "${REMOTE}scripts/"

echo "== 5/6 brand + restart =="
ssh "$SSH_HOST" "rm -f /opt/mineworld/dist/web/mw_touch_pad.js /opt/mineworld/godot/spike/web/mw_touch_pad.js \
  && python3 /opt/mineworld/scripts/inject_site_branding.local.py /opt/mineworld \
  && sudo systemctl restart mineworld-web mineworld-gateway \
  && systemctl is-active mineworld-web mineworld-gateway"

echo "== 6/6 verify =="
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$SITE_URL")"
[[ "$code" == "200" ]] || { echo "ERROR: site returned $code" >&2; exit 1; }
served="$(curl -s --max-time 15 "$SITE_URL" | grep -o 'MW_BUILD="[^"]*"' | head -1)"
echo "site 200 · served $served"
[[ "$served" == "MW_BUILD=\"$MW_BUILD\"" ]] || { echo "ERROR: build mismatch (cache?)" >&2; exit 1; }
# P1-1a: gzip must be on for the big artifacts (wasm/pck) — fail loudly if not.
enc="$(curl -sI -H 'Accept-Encoding: gzip' --max-time 15 "${SITE_URL}index.wasm" | grep -i '^content-encoding:' | tr -d '\r' | awk '{print $2}')"
echo "wasm content-encoding: ${enc:-none}"
[[ "$enc" == "gzip" || "$enc" == "br" ]] || { echo "ERROR: index.wasm not compressed (gzip/br)" >&2; exit 1; }
echo "DEPLOY OK $MW_BUILD — hard-refresh (Cmd+Shift+R) to see it"
