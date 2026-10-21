#!/bin/zsh
# Build the saver in Release and install it for the current user.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate --quiet
xcodebuild -project SolitaireSaver.xcodeproj -scheme SolitaireSaver -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build build | grep -E 'error|BUILD' || true

src="build/Build/Products/Release/Solitaire Win.saver"
dest="$HOME/Library/Screen Savers"
[[ -d "$src" ]] || { echo "build failed"; exit 1; }
mkdir -p "$dest"
rm -rf "$dest/Solitaire Win.saver"
cp -R "$src" "$dest/"
# The host process caches loaded savers; restart it so the new build is used.
killall legacyScreenSaver 2>/dev/null || true
echo "Installed to $dest/Solitaire Win.saver — pick it in System Settings → Screen Saver."
