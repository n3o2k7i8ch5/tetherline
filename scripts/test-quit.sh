#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/quit-smoke
xcrun swiftc -swift-version 6 -D UI_PREVIEW -parse-as-library -target arm64-apple-macosx14.0 \
    Sources/TetherlineCore/*.swift App/*.swift Tests/QuitSmoke/Smoke.swift \
    -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Security -framework CoreWLAN \
    -o .build/quit-smoke/QuitSmoke
.build/quit-smoke/QuitSmoke
