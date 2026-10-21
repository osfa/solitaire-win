#!/bin/zsh
# Screenshot every effect on its own (and a few stacks) for docs/effects. Needs a Release harness build and ImageMagick.
set -euo pipefail
cd "${0:A:h}/.."

app="build/Build/Products/Release/Solitaire Harness.app/Contents/MacOS/Solitaire Harness"
out="docs/effects/img"
tmp=$(mktemp -d)
mkdir -p "$out"
"$app" -list YES > docs/effects/effects.json

shoot() { # slug, effects, seconds until the snapshot
  local -a extra=()
  [[ -n $2 ]] && extra=(-effect "$2")
  rm -f "$tmp/snap-00.png"
  "$app" -seed 42 -chaos 0 "${extra[@]}" -effectat 4 -snap "$tmp" -snaps 1 -every "$3" > /dev/null 2>&1
  magick "$tmp/snap-00.png" -resize 960x -quality 85 "$out/$1.jpg"
  echo "$1"
}

shoot normal "" 8
python3 -I -c '
import json, sys
for e in json.load(open("docs/effects/effects.json")):
    # Effects are forced at 3x duration; snap inside the effect but after it has had time to show.
    at = 4 + min(max(e["durationMin"] * 3 * 0.6, 0.4), 4)
    print(e["name"], "%.1f" % at, sep="\t")
' | while IFS=$'\t' read -r name at; do
  shoot "${name// /-}" "$name" "$at"
done

shoot stack-cycle-rainbow "card cycle,rainbow cards" 9
shoot stack-orbit-walls-rainbow "orbit,walls,rainbow cards" 10
shoot stack-phosphor-slices-melt "phosphor,slices,melt" 7
shoot stack-split-crowd-super-bounce "split,crowd,super bounce" 10
rm -rf "$tmp"
