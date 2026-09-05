#!/bin/sh
# Runs `swift` from the newest release toolchain installed for the user (see update-toolchain.sh),
# falling back to the system toolchain. Vien tracks the latest Swift release deliberately.
latest="$HOME/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift"
if [ -x "$latest" ]; then exec "$latest" "$@"; fi
exec swift "$@"
