#!/bin/zsh
# Builds a release iDump.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/iDump"

APP="build/iDump.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/iDump"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so macOS will launch it locally.
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run it with: open $APP   (or drag it into /Applications)"
