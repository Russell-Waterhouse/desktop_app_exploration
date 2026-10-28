#!/usr/bin/env bash
# Start a local test server for the files in this directory, in the
# background, so apps can download recipes.json from localhost while
# you QA them. Stop it with ./kill_server.sh.
# Usage: ./run_server.sh [port]   (default port: 8000)
set -euo pipefail

cd "$(dirname "$0")"

PORT="${1:-${PORT:-8000}}"
PID_FILE=".server.pid"
LOG_FILE="server.log"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE")"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Server already running (PID $OLD_PID) at http://localhost:$PORT/recipes.json"
    exit 0
  fi
  # Stale PID file: the server is gone, so remove it and start fresh.
  rm -f "$PID_FILE"
fi

nohup python3 -m http.server "$PORT" --directory "$PWD" --bind 127.0.0.1 \
  >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"

# Wait briefly for the server to answer before reporting success.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -s -o /dev/null "http://localhost:$PORT/recipes.json"; then
    echo "Server running (PID $(cat "$PID_FILE")) at http://localhost:$PORT/recipes.json"
    echo "Stop it with ./kill_server.sh (log: $LOG_FILE)"
    exit 0
  fi
  sleep 0.5
done

echo "Server did not start; see $LOG_FILE" >&2
rm -f "$PID_FILE"
exit 1
