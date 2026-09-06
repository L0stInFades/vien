#!/bin/sh
# Builds Vien in release mode and assembles dist/Vien.app (ad-hoc signed). No Xcode needed.
# UNIVERSAL=1 builds arm64 and x86_64 separately and joins them with lipo (what releases ship).
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
config="${1:-release}"

build() {  # build [--triple …] → prints the binary's path
  log="$(mktemp)"
  if ! "$here/Scripts/swift.sh" build -c "$config" --product Vien "$@" >"$log" 2>&1; then
    grep -E "error" "$log" >&2; rm -f "$log"; echo "build failed" >&2; exit 1
  fi
  grep -E "warning: unre" "$log" >&2 || true; rm -f "$log"
}
if [ "${UNIVERSAL:-0}" = "1" ]; then
  build --triple arm64-apple-macosx15.0
  build --triple x86_64-apple-macosx15.0
  bin="$(mktemp)"
  lipo -create ".build/arm64-apple-macosx/$config/Vien" ".build/x86_64-apple-macosx/$config/Vien" -output "$bin"
else
  build
  bin=".build/$config/Vien"
fi
app="dist/Vien.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Vien"
chmod +x "$app/Contents/MacOS/Vien"
cp Info.plist "$app/Contents/Info.plist"
cp -R Resources/. "$app/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$app/Contents/Info.plist" >/dev/null 2>&1 || true
commit="$(git -C "$here" rev-parse --short HEAD 2>/dev/null || true)"
[ -n "$commit" ] && /usr/libexec/PlistBuddy -c "Add :VienCommit string $commit" "$app/Contents/Info.plist" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements /dev/null "$app" 2>/dev/null || codesign --force --sign - "$app"
echo "→ $app ($(du -sh "$app" | cut -f1), $(lipo -archs "$app/Contents/MacOS/Vien"))"
