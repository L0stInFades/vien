#!/bin/sh
# Builds Vien in release mode and assembles dist/Vien.app (ad-hoc signed). No Xcode needed.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
config="${1:-release}"

"$here/Scripts/swift.sh" build -c "$config" --product Vien 2>&1 | grep -E "error|warning: unre|Compiling|Build" || true
bin=".build/$config/Vien"
[ -x "$bin" ] || { echo "build failed" >&2; exit 1; }
app="dist/Vien.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Vien"
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/. "$app/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements /dev/null "$app" 2>/dev/null || codesign --force --sign - "$app"
echo "→ $app ($(du -sh "$app" | cut -f1))"
