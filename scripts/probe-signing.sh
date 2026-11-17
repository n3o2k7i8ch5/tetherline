#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
action=${1:-status}
app=/Applications/TetherlineSigningProbe.app
case "$action" in
prepare)
    ./scripts/check-signing.sh
    [[ ! -e "$app" ]] || { echo 'Próba już istnieje; użyj status lub cleanup.' >&2; exit 1; }
    identity=$(/usr/bin/security find-identity -v -p codesigning | awk '/"Apple Development:/ {print $2; exit}')
    mkdir -p .build/signing-probe
    stage=$(mktemp -d "$PWD/.build/signing-probe/stage.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    bundle="$stage/TetherlineSigningProbe.app"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Library/LaunchDaemons"
    xcrun swiftc Tests/SigningProbe/main.swift -framework ServiceManagement -o "$bundle/Contents/MacOS/Probe"
    xcrun swiftc Tests/SigningProbe/helper.swift -o "$bundle/Contents/MacOS/helper"
    python3 - "$bundle" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1]) / 'Contents'
with (p / 'Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='pl.tetherline.signing-probe', CFBundleName='Tetherline Signing Probe',
                      CFBundleExecutable='Probe', CFBundlePackageType='APPL', CFBundleVersion='1', LSUIElement=True), f)
with (p / 'Library/LaunchDaemons/pl.tetherline.signing-probe.plist').open('wb') as f:
    plistlib.dump(dict(Label='pl.tetherline.signing-probe', BundleProgram='Contents/MacOS/helper',
                      ProgramArguments=['helper'], RunAtLoad=True, KeepAlive=True, ProcessType='Standard'), f)
PY
    codesign --force --options runtime --timestamp=none --sign "$identity" "$bundle/Contents/MacOS/helper"
    codesign --force --options runtime --timestamp=none --sign "$identity" "$bundle"
    codesign --verify --deep --strict "$bundle"
    ditto "$bundle" "$app"
    echo 'Gotowe. scripts/probe-signing.sh register'
    ;;
register|settings)
    "$app/Contents/MacOS/Probe" "$action"
    ;;
status)
    "$app/Contents/MacOS/Probe" status
    /bin/launchctl print system/pl.tetherline.signing-probe
    ;;
cleanup)
    "$app/Contents/MacOS/Probe" unregister
    if /bin/launchctl print system/pl.tetherline.signing-probe >/dev/null 2>&1; then
        echo 'Usługa jeszcze się zatrzymuje; ponów cleanup.' >&2; exit 1
    fi
    rm -rf "$app"
    ;;
*) echo 'Użycie: probe-signing.sh prepare|register|settings|status|cleanup' >&2; exit 1 ;;
esac

