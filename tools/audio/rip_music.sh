#!/usr/bin/env bash
# Issue #16: bring the owner's music into the game. Re-encodes each track to MP3
# (160 kb/s, loops in Godot; this ffmpeg has no Vorbis encoder) at one loudness, so no track jumps out.
#
# Run: tools/audio/rip_music.sh [source dir]   (default ~/Desktop/Music; needs ffmpeg)
# Expects Ambient1..3, Battle, "Battle 2" and Space (.mp3). Writes assets/audio/music/*.mp3.
# Which track plays when is content/look/sound.json, not this script.
set -euo pipefail

SRC="${1:-$HOME/Desktop/Music}"
OUT="$(cd "$(dirname "$0")/../.." && pwd)/assets/audio/music"
mkdir -p "$OUT"

for name in Ambient1 Ambient2 Ambient3 Battle "Battle 2" Space; do
  in="$SRC/$name.mp3"
  [ -f "$in" ] || { echo "missing $in" >&2; exit 1; }
  out="$OUT/$(echo "$name" | tr -d ' ' | tr '[:upper:]' '[:lower:]').mp3"
  ffmpeg -hide_banner -loglevel error -y -i "$in" -map_metadata -1 \
    -af "loudnorm=I=-18:TP=-1.5:LRA=11" -ar 44100 -c:a libmp3lame -b:a 160k "$out"
  echo "wrote $out"
done
