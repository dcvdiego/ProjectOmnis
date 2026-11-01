#!/usr/bin/env bash
# Two-process smoke test: a headless dedicated server and a headless client.
# Usage: GODOT=/path/to/godot tests/smoke_multiplayer.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
PORT="${PORT:-24690}"
LOG_DIR="$(mktemp -d)"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . --quit-after 600 -- --server --port="$PORT" >"$LOG_DIR/server.log" 2>&1 &
SERVER_PID=$!
sleep 2
"$GODOT" --headless --path . --quit-after 240 -- --join=127.0.0.1 --port="$PORT" >"$LOG_DIR/client.log" 2>&1 || true
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true

echo "--- server"; cat "$LOG_DIR/server.log"
echo "--- client"; cat "$LOG_DIR/client.log"

fail=0
grep -q "Dedicated server running on port $PORT" "$LOG_DIR/server.log" || { echo "FAIL: server did not start"; fail=1; }
grep -qE "Player [0-9]+ joined \(1 online\)" "$LOG_DIR/server.log" || { echo "FAIL: client did not join"; fail=1; }
grep -qE "Local player [0-9]+ spawned" "$LOG_DIR/client.log" || { echo "FAIL: client's player was not replicated"; fail=1; }
if grep -qE "SCRIPT ERROR|^ERROR" "$LOG_DIR/server.log" "$LOG_DIR/client.log"; then
  echo "FAIL: errors in logs"; fail=1
fi
[ "$fail" = 0 ] && echo "PASS: multiplayer smoke test"
exit "$fail"
