#!/bin/bash
# Builds the downloadable disk image build/Tetherline-<version>.dmg and its SHA-256.
#
#     scripts/package-release.sh [vX.Y.Z]
#
# With a tag, refuses to package when it differs from the app version.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
if [[ $# -gt 0 && "$1" != "v$version" ]]; then
    echo "Tag $1 does not match the app version $version in Resources/Info.plist." >&2
    exit 1
fi
scripts/build.sh >/dev/null
name="Tetherline-$version.dmg"
dmg="$PWD/build/$name"
staging=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
mount="$staging/mount"
cleanup() {
    if [[ -d "$mount" ]]; then hdiutil detach -quiet "$mount" || true; fi
    rm -rf "$staging"
}
trap cleanup EXIT
mkdir "$staging/image" "$mount"
ditto build/Tetherline.app "$staging/image/Tetherline.app"
# The app runs only from /Applications; the image offers the drag target.
ln -s /Applications "$staging/image/Applications"
rm -f "$dmg" "$dmg.sha256"
# hdiutil occasionally reports a busy resource on build machines; retry briefly.
for attempt in 1 2 3; do
    if hdiutil create -quiet -volname Tetherline -srcfolder "$staging/image" -fs HFS+ -format UDZO "$dmg"; then break; fi
    if [[ $attempt == 3 ]]; then exit 1; fi
    sleep 5
done
hdiutil verify -quiet "$dmg"
# Check what a downloader gets: an intact, universal app.
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$dmg"
codesign --verify --deep --strict "$mount/Tetherline.app"
for executable in Tetherline TetherlineControl muta; do
    archs=$(lipo -archs "$mount/Tetherline.app/Contents/MacOS/$executable")
    [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || { echo "$executable is not universal: $archs" >&2; exit 1; }
done
hdiutil detach -quiet "$mount"
rmdir "$mount"
(cd build && shasum -a 256 "$name" > "$name.sha256")
echo "$dmg"
