#!/usr/bin/env bash
# Issue #401: LAN play on loopback, across real processes. A host and two guests
# in a game capped at two: the walker is let in and walks 10 m (the host's copy
# ends within 0.5 m inside 1 s), the late guest is turned away as full, and the
# walker quitting leaves the host's roster. See scenes/lan_trace.gd.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
PORT="${LAN_TRACE_PORT:-24991}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; kill $(jobs -p) 2>/dev/null' EXIT
run() { perl -e 'alarm 60; exec @ARGV' "$GODOT_BIN" --headless --path . -s res://scenes/lan_trace.gd -- "$1" "$PORT" > "$tmp/$1.log" 2>&1; echo $? > "$tmp/$1.code"; }
run host & sleep 1.5
run walker & run late &
wait
status=0
for r in host walker late; do
  grep -E 'LAN_TRACE|SCRIPT ERROR|^ERROR' "$tmp/$r.log"
  if [ "$(cat "$tmp/$r.code")" != "0" ] || grep -Eq 'SCRIPT ERROR:|^ERROR:' "$tmp/$r.log"; then
    echo "FAIL: $r (exit $(cat "$tmp/$r.code"))" >&2
    status=1
  fi
done
[ $status = 0 ] && echo "LAN loopback: PASS"
exit $status
