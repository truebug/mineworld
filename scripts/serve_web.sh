#!/usr/bin/env bash
# Local Web demo server (static Godot export + /api/recordings).
# Frees the listen port before start/restart so you don't hit stale code.
#
# Usage (from repo root):
#   bash scripts/serve_web.sh start
#   bash scripts/serve_web.sh restart
#   bash scripts/serve_web.sh stop
#   bash scripts/serve_web.sh status
#   bash scripts/serve_web.sh restart --port 8080
#
# Env: PORT=8080 HOST=127.0.0.1 PYTHON=.venv/bin/python
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
PYTHON="${PYTHON:-$ROOT/.venv/bin/python}"
if [[ ! -x "$PYTHON" ]]; then
  PYTHON="$(command -v python3)"
fi

CMD="${1:-restart}"
shift || true

# Optional: --port N before/after other flags forwarded to serve_web_demo.py
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      EXTRA+=(--port "$2")
      shift 2
      ;;
    --host)
      HOST="$2"
      EXTRA+=(--host "$2")
      shift 2
      ;;
    *)
      EXTRA+=("$1")
      shift
      ;;
  esac
done

listening_pids() {
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true
}

cmd_stop() {
  local pids
  pids="$(listening_pids)"
  if [[ -z "$pids" ]]; then
    echo "serve_web: nothing listening on ${HOST}:${PORT}"
    return 0
  fi
  echo "serve_web: stopping PID(s) on :${PORT}: $pids"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 0.3
  pids="$(listening_pids)"
  if [[ -n "$pids" ]]; then
    echo "serve_web: force kill $pids"
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
  echo "serve_web: stopped"
}

cmd_status() {
  local pids
  pids="$(listening_pids)"
  if [[ -z "$pids" ]]; then
    echo "serve_web: :${PORT} free"
    return 0
  fi
  echo "serve_web: :${PORT} in use by PID(s): $pids"
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
}

cmd_start() {
  if [[ ! -f "$ROOT/dist/web/index.html" ]]; then
    echo "ERROR: missing dist/web/index.html — run: bash scripts/export_godot.sh web" >&2
    exit 1
  fi
  local pids
  pids="$(listening_pids)"
  if [[ -n "$pids" ]]; then
    echo "serve_web: replacing PID(s) on :${PORT}: $pids"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 0.3
    pids="$(listening_pids)"
    if [[ -n "$pids" ]]; then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
      sleep 0.2
    fi
  fi
  echo "serve_web: starting http://${HOST}:${PORT}/"
  # Don't exec: keep shell semantics friendly when launched with & / nohup.
  "$PYTHON" "$ROOT/scripts/serve_web_demo.py" --host "$HOST" --port "$PORT" "${EXTRA[@]}"
}

case "$CMD" in
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  restart)
    cmd_stop
    cmd_start
    ;;
  status)
    cmd_status
    ;;
  -h|--help|help)
    sed -n '2,14p' "$0"
    ;;
  *)
    echo "Usage: bash scripts/serve_web.sh {start|stop|restart|status} [--port N] [--host H]" >&2
    exit 1
    ;;
esac
