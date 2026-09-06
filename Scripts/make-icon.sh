#!/bin/sh
# Regenerates Resources/AppIcon.icns from Scripts/make-icon.swift. No design tool involved.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
swiftc="$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc"
[ -x "$swiftc" ] || swiftc=swiftc
tmp="$(mktemp -d)"
"$swiftc" -O -sdk "$(xcrun --show-sdk-path)" "$here/Scripts/make-icon.swift" -o "$tmp/make-icon"
"$tmp/make-icon" "$tmp/AppIcon.iconset"
iconutil -c icns "$tmp/AppIcon.iconset" -o "$here/Resources/AppIcon.icns"
sips -z 256 256 "$tmp/AppIcon.iconset/icon_512x512.png" --out "$tmp/preview.png" >/dev/null
echo "→ $here/Resources/AppIcon.icns (preview: $tmp/preview.png)"
