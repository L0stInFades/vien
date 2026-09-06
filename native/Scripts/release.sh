#!/bin/sh
# Builds, signs, notarizes and packages a release:
#   dist/Vien-<version>.zip   the app (what the in-app updater installs)
#   dist/Vien-<version>.dmg   for humans
#   dist/appcast.json         what the in-app updater reads (attach all three to the GitHub release)
#
# Usage: Scripts/release.sh <version> [build-number]
# Environment:
#   SIGN_IDENTITY          "Developer ID Application: Name (TEAMID)"; ad-hoc signature when unset
#   NOTARY_PROFILE         keychain profile saved with `xcrun notarytool store-credentials`, or
#   APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD   (an app-specific password)
#   REQUIRE_NOTARIZATION=1 fail instead of skipping when credentials are missing (CI)
#   RELEASE_NOTES          file whose text goes into the appcast (default: the last commit subject)
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
version="${1:?usage: release.sh <version> [build-number]}"
build="${2:-$(git rev-list --count HEAD)}"

Scripts/bundle.sh release
app="dist/Vien.app"
# The version lives in the bundle, not in the tracked Info.plist: the tag decides it.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
  codesign --verify --deep --strict "$app"
else
  echo "note: SIGN_IDENTITY is unset; ad-hoc signature (fine locally, not for distribution)"
  codesign --force --deep --sign - "$app"
fi

zip="dist/Vien-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

notarize() {
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  else
    return 2
  fi
}

if [ -n "${SIGN_IDENTITY:-}" ] && notarize "$zip"; then
  xcrun stapler staple "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"   # the archive must contain the stapled app
elif [ "${REQUIRE_NOTARIZATION:-0}" = "1" ]; then
  echo "error: notarization is required but SIGN_IDENTITY and notarytool credentials are not all set" >&2
  exit 1
else
  echo "note: not notarized (no credentials)"
fi

# Disk image with an Applications link.
root="$(mktemp -d)"
cp -R "$app" "$root/"
ln -s /Applications "$root/Applications"
dmg="dist/Vien-$version.dmg"
rm -f "$dmg"
hdiutil create -volname Vien -srcfolder "$root" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$root"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$dmg"
  if notarize "$dmg"; then xcrun stapler staple "$dmg"; fi
fi

# Appcast for the in-app updater.
sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
repo="$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
url="https://github.com/$repo/releases/download/native-v$version/Vien-$version.zip"
notes="$(if [ -n "${RELEASE_NOTES:-}" ]; then cat "$RELEASE_NOTES"; else git log -1 --pretty=%s; fi)"
NOTES="$notes" /usr/bin/python3 - "$version" "$build" "$url" "$sha" > dist/appcast.json <<'PY'
import json, os, sys
version, build, url, sha = sys.argv[1:5]
print(json.dumps({"version": version, "build": build, "minimumSystemVersion": "15.0", "url": url, "sha256": sha, "notes": os.environ.get("NOTES", "")}, indent=2))
PY
echo "→ $zip, $dmg, dist/appcast.json (version $version build $build)"
