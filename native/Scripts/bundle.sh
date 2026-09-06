#!/bin/sh
# Builds Vien in release mode and assembles dist/Vien.app (ad-hoc signed). No Xcode needed.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
config="${1:-release}"

log="$(mktemp)"
if ! "$here/Scripts/swift.sh" build -c "$config" --product Vien >"$log" 2>&1; then
  grep -E "error" "$log" >&2; rm -f "$log"; echo "build failed" >&2; exit 1
fi
grep -E "warning: unre|Build" "$log" || true; rm -f "$log"
bin=".build/$config/Vien"
app="dist/Vien.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Vien"
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/. "$app/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist" >/dev/null 2>&1 || true
commit="$(git -C "$here" rev-parse --short HEAD 2>/dev/null || true)"
[ -n "$commit" ] && /usr/libexec/PlistBuddy -c "Add :VienCommit string $commit" "$app/Contents/Info.plist" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements /dev/null "$app" 2>/dev/null || codesign --force --sign - "$app"
echo "→ $app ($(du -sh "$app" | cut -f1))"
