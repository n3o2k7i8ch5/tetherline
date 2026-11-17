#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local development needs no Apple account or certificate. Certificate signing
# is opt-in; the ad-hoc signature is enough to launch the app on Apple Silicon.
identity=${SIGN_IDENTITY:--}
vendor=$(python3 scripts/fetch-muta.py)
app="$PWD/build/Tetherline.app"
staging=$(mktemp -d "$PWD/.build/bundle.XXXXXX")
trap 'rm -rf "$staging"' EXIT
bundle="$staging/Tetherline.app"
mkdir -p "$bundle/Contents/"{MacOS,Resources}
xcrun swiftc -swift-version 6 -O -parse-as-library -target arm64-apple-macosx14.0 \
    Sources/TetherlineCore/*.swift App/*.swift \
    -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Security -framework CoreWLAN \
    -o "$bundle/Contents/MacOS/Tetherline"
# The root controller gets only the code it runs, so unrelated app changes
# do not alter its digest and do not ask for an administrator update.
xcrun swiftc -swift-version 6 -O -parse-as-library -target arm64-apple-macosx14.0 \
    $(scripts/control-sources.sh) \
    -o "$bundle/Contents/MacOS/TetherlineControl"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/pl.tetherline.muta.plist "$bundle/Contents/Resources/"
cp "$vendor/muta" "$bundle/Contents/MacOS/muta"
cp "$vendor/LICENSE" "$bundle/Contents/Resources/muta-LICENSE.txt"
cp Vendor/muta.version "$bundle/Contents/Resources/muta.version"
cp -R Resources/en.lproj Resources/pl.lproj "$bundle/Contents/Resources/"
if [[ ! -f .build/AppIcon.icns || scripts/render-app-icon.swift -nt .build/AppIcon.icns ]]; then
    xcrun swift scripts/render-app-icon.swift "$PWD/.build/AppIcon.iconset"
    iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$bundle/Contents/Resources/"
codesign --force --options runtime --timestamp=none --sign "$identity" "$bundle/Contents/MacOS/muta"
codesign --force --options runtime --timestamp=none --sign "$identity" "$bundle/Contents/MacOS/TetherlineControl"
codesign --force --options runtime --timestamp=none --sign "$identity" "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
mkdir -p build
if [[ -e "$app" ]]; then rm -rf "$app"; fi
mv "$bundle" "$app"
echo "$app"

