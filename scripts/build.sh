#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/CLI Speed Reader.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
cp images/cli-speed-reader.icns "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" Sources/*.swift -o "$app/Contents/MacOS/RSVP-ORP"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built: $app"
ditto "$app" "/Applications/CLI Speed Reader.app"
touch "/Applications/CLI Speed Reader.app"
echo "Installed: /Applications/CLI Speed Reader.app"
