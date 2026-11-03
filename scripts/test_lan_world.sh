#!/usr/bin/env bash
# Issue #402: one town for two players on loopback, each process with a town. The
# guest's people are all copies of the host's, and the guest's kill counts in both
# games. See scenes/lan_world_trace.gd. Both towns read and write user://save.json,
# so it is backed up and put back.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
PORT="${LAN_TRACE_PORT:-24992}"
tmp="$(mktemp -d)"
name="$(sed -n 's/^config\/name="\(.*\)"/\1/p' project.godot | head -1)"
case "$(uname)" in
  Darwin) ud="$HOME/Library/Application Support/Godot/app_userdata/$name" ;;
  *) ud="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/$name" ;;
esac
[ -f "$ud/save.json" ] && cp "$ud/save.json" "$tmp/save.bak"
trap '[ -f "$tmp/save.bak" ] && cp "$tmp/save.bak" "$ud/save.json"; [ -n "${LAN_TRACE_LOGS:-}" ] && cp "$tmp"/*.log "$LAN_TRACE_LOGS"/; rm -rf "$tmp"; kill $(jobs -p) 2>/dev/null' EXIT
run() { perl -e 'alarm 150; exec @ARGV' "$GODOT_BIN" --headless --path . -s res://scenes/lan_world_trace.gd -- "$1" "$PORT" > "$tmp/$1.log" 2>&1; echo $? > "$tmp/$1.code"; }
run host & sleep 2
run guest &
wait
status=0
for r in host guest; do
  grep -E 'LAN_WORLD|SCRIPT ERROR' "$tmp/$r.log"
  if [ "$(cat "$tmp/$r.code")" != "0" ] || grep -Eq 'SCRIPT ERROR:' "$tmp/$r.log"; then
    echo "FAIL: $r (exit $(cat "$tmp/$r.code"))" >&2
    status=1
  fi
done
[ $status = 0 ] && echo "LAN one town: PASS"
exit $status
