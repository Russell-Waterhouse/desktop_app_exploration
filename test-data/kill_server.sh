#!/usr/bin/env bash
# Stop the local test server started by ./run_server.sh.
# It kills only the PID recorded in .server.pid, not any other server.
set -u

cd "$(dirname "$0")"

PID_FILE=".server.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No server running (no $PID_FILE found)."
  exit 0
fi

PID="$(cat "$PID_FILE")"

if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
  echo "Server already stopped; removing stale $PID_FILE."
  rm -f "$PID_FILE"
  exit 0
fi

kill "$PID"

# Give it a few seconds to exit cleanly, then force it if needed.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if kill -0 "$PID" 2>/dev/null; then
  kill -9 "$PID" 2>/dev/null || true
  echo "Server (PID $PID) did not stop cleanly, so it was force-killed."
else
  echo "Server (PID $PID) stopped."
fi

rm -f "$PID_FILE"
