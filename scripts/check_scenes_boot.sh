#!/usr/bin/env bash
# Boot each main scene headless (autoloads active) and fail on any script
# compile error. Catches what Web export + gdscript_lint cannot: cross-file
# signature drift, missing var declarations, scene/script wiring breakage.
set -u
GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "$0")/../godot/spike" && pwd)"
SCENES="${MW_CHECK_SCENES:-res://demo_hub.tscn res://demo_race.tscn res://demo_workshop.tscn res://demo_city.tscn}"
BOOT_S="${MW_CHECK_BOOT_S:-12}"
fail=0
for scene in $SCENES; do
  log="/tmp/mw_boot_$(basename "$scene" .tscn).log"
  "$GODOT" --headless --rendering-driver dummy --path "$PROJ" "$scene" > "$log" 2>&1 &
  pid=$!
  sleep "$BOOT_S"
  # SIGKILL, not SIGTERM: graceful shutdown crashes in the macOS Metal
  # teardown path (Abort trap 6) and pops a crash-report dialog every run.
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  hits=$(grep -cE "SCRIPT ERROR|Parse Error|Compile Error" "$log" || true)
  if [ "$hits" -gt 0 ]; then
    echo "BOOT FAIL $scene — $hits script error(s):"
    grep -E "SCRIPT ERROR|Parse Error|Compile Error" "$log" | head -4
    fail=1
  else
    echo "BOOT OK   $scene"
  fi
done
exit "$fail"
