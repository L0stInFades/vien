#!/bin/sh
# Installs the newest Swift release toolchain from swift.org into ~/Library/Developer/Toolchains
# (no administrator rights needed) and points `swift-latest` at it. Re-run any time to roll forward.
set -eu
version="$(curl -sSL https://www.swift.org/api/v1/install/releases.json | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)[-1]["name"])')"
[ -n "$version" ] || { echo "could not find the latest release on swift.org" >&2; exit 1; }
dir="$HOME/Library/Developer/Toolchains"
if [ -d "$dir/swift-${version}-RELEASE.xctoolchain" ]; then echo "Swift ${version} is already installed"; exit 0; fi
tmp="$(mktemp -d)"
url="https://download.swift.org/swift-${version}-release/xcode/swift-${version}-RELEASE/swift-${version}-RELEASE-osx.pkg"
echo "downloading Swift ${version}..."
curl -sSL -o "$tmp/swift.pkg" "$url"
installer -pkg "$tmp/swift.pkg" -target CurrentUserHomeDirectory >/dev/null
rm -rf "$tmp"
echo "installed: $("$dir/swift-latest.xctoolchain/usr/bin/swift" --version | head -1)"
