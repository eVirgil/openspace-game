#!/usr/bin/env bash
# Builds the shared builds (export feature "share", see docs/SHARING.md) and zips
# them for sending. Needs the Godot export templates for the pinned version.
# Run: ./scripts/package.sh [windows|mac|all]   (default: all)
# Out: "builds/OpenSpace V<version> Windows.zip", "builds/OpenSpace V<version> Mac.zip",
# where <version> is application/config/version in project.godot (the only place
# to bump it; the export presets leave their version fields empty so they use it).
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/godot ]; then GODOT_BIN=/opt/homebrew/bin/godot; fi
  if [ -x /usr/local/bin/godot ]; then GODOT_BIN=/usr/local/bin/godot; fi
fi

PIN="$(cat scripts/pin.txt)"
GODOT_VER="$("$GODOT_BIN" --version 2>/dev/null || true)"
case "$GODOT_VER" in
  "$PIN".stable*) ;;
  *) echo "package: Godot $PIN is pinned, found '$GODOT_VER'" >&2; exit 1 ;;
esac
VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)"
if [ -z "$VERSION" ]; then
  echo "package: no config/version in project.godot" >&2
  exit 1
fi
NAME="OpenSpace V$VERSION"

TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$PIN.stable"

need_template() {
  if [ ! -f "$TEMPLATES/$1" ]; then
    echo "package: missing export template $TEMPLATES/$1" >&2
    echo "package: install the $PIN templates (Editor > Manage Export Templates)" >&2
    exit 1
  fi
}

# Godot can exit zero after a failed export, so check its log and the output too.
export_preset() {
  local preset="$1" out="$2" log
  log="$(mktemp)"
  echo "package: exporting '$preset' -> $out"
  "$GODOT_BIN" --headless --path . --export-release "$preset" "$out" 2>&1 | tee "$log" | grep -E "ERROR|WARNING|savepack" || true
  if grep -q '^ERROR:' "$log" || [ ! -e "$out" ]; then
    echo "package: export of '$preset' failed (log: $log)" >&2
    exit 1
  fi
  rm -f "$log"
}

build_windows() {
  need_template windows_release_x86_64.exe
  local zip="builds/$NAME Windows.zip"
  rm -rf builds/windows "$zip"
  mkdir -p "builds/windows/$NAME"
  export_preset "Windows Share" "builds/windows/$NAME/$NAME.exe"
  # The zip unpacks to a folder named like the game.
  (cd builds/windows && zip -qr "../$NAME Windows.zip" "$NAME")
  echo "package: $zip ($(du -h "$zip" | cut -f1))"
}

build_mac() {
  need_template macos.zip
  local app="builds/macos/$NAME.app" zip="builds/$NAME Mac.zip"
  rm -rf builds/macos "$zip"
  mkdir -p builds/macos
  export_preset "macOS Share" "$app"
  codesign --verify --deep "$app"
  # ditto keeps the bundle's signature and symlinks; plain zip can break them.
  ditto -c -k --keepParent "$app" "$zip"
  echo "package: $zip ($(du -h "$zip" | cut -f1))"
}

# Textures and class names must be imported before an export can use them.
echo "package: using $GODOT_VER; importing project..."
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

case "${1:-all}" in
  windows) build_windows ;;
  mac) build_mac ;;
  all) build_windows; build_mac ;;
  *) echo "usage: $0 [windows|mac|all]" >&2; exit 2 ;;
esac
