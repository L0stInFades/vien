#!/bin/sh
# Builds (debug) and launches Vien from the package for a quick look. Pass a file or folder to open.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

"$here/Scripts/swift.sh" build --product Vien 2>&1 | grep -E "error|Build" || true
exec .build/debug/Vien "$@"
