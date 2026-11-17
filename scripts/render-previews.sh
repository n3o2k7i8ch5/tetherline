#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/.build/ui-preview/TetherlinePreview.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/previews
cp Resources/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier pl.tetherline.preview' "$app/Contents/Info.plist"
cp -R Resources/en.lproj Resources/pl.lproj "$app/Contents/Resources/"
cp Vendor/muta.version "$app/Contents/Resources/"
xcrun swiftc -swift-version 6 -D UI_PREVIEW -parse-as-library -target arm64-apple-macosx14.0 \
    Sources/TetherlineCore/*.swift App/*.swift Tests/UIPreview/Preview.swift \
    -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Security -framework CoreWLAN \
    -o "$app/Contents/MacOS/Tetherline"
codesign --force --sign - "$app"
states=("$@")
if [[ ${#states[@]} -eq 0 ]]; then
    states=(off setup starting stopping connected route waiting failed conflict approval operation-failed settings)
fi
for language in en pl; do
    for theme in light dark; do
        for state in "${states[@]}"; do
            "$app/Contents/MacOS/Tetherline" "$PWD/.build/previews/$language-$theme-$state.png" "$state" "$theme" -AppleLanguages "($language)"
        done
    done
done
