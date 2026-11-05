#!/usr/bin/env bash
# Issue #548: the IP rule covers commit messages too (README). Every commit this
# branch adds over the base (default origin/main) is checked, subject and body,
# against content/core/llm/ip_blocklist.json. The GUT scan
# (tests/test_ip_neutral.gut.gd) covers the files and their names.
# Run: ./scripts/check_commit_messages.sh [base]
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="${1:-origin/main}"
if ! git rev-parse --verify -q "$BASE" >/dev/null 2>&1; then
  echo "commit messages: no $BASE here, not checked"
  exit 0
fi

TERMS_FILE="$(mktemp)"
trap 'rm -f "$TERMS_FILE"' EXIT
python3 -c 'import json,sys; print("\n".join(t for t in json.load(open(sys.argv[1]))["terms"] if t))' \
  content/core/llm/ip_blocklist.json > "$TERMS_FILE"
if [ ! -s "$TERMS_FILE" ]; then
  echo "commit messages: ERROR -- the IP blocklist did not load" >&2
  exit 1
fi

BAD=""
COUNT=0
for c in $(git rev-list "$BASE"..HEAD); do
  COUNT=$((COUNT + 1))
  if git log -1 --format=%B "$c" | grep -q -i -F -f "$TERMS_FILE"; then
    BAD="$BAD$(git log -1 --format='%h %s' "$c")"$'\n'
  fi
done

if [ -n "$BAD" ]; then
  echo "commit messages: ERROR -- these name a franchise term (reword them):" >&2
  printf '%s' "$BAD" >&2
  exit 1
fi
echo "commit messages: clean ($COUNT checked against $BASE)"
