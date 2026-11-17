#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/visibility-smoke
xcrun swiftc -swift-version 6 -D UI_PREVIEW -parse-as-library -target arm64-apple-macosx14.0 \
    Sources/TetherlineCore/*.swift App/*.swift Tests/VisibilitySmoke/Smoke.swift \
    -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Security -framework CoreWLAN \
    -o .build/visibility-smoke/VisibilitySmoke
.build/visibility-smoke/VisibilitySmoke
