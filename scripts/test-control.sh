#!/bin/bash
# Root test of the isolated probe deployment: installer, controller, start/stop,
# boot override and uninstall, with a stand-in engine (no muta, no USB).
#   --prepare-only        build and write the script for review, no prompt
#   --install-production  after every probe check passes, install/update
#                         build/Tetherline.app's components in the same session
set -euo pipefail
cd "$(dirname "$0")/.."
base="$PWD/.build/control-probe"
mkdir -p "$base"
swiftc() { xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macosx14.0 "$@"; }
xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 Tests/ControlProbe/Engine.swift -o "$base/engine"
swiftc -D CONTROL_PROBE $(scripts/control-sources.sh) -o "$base/controller"
swiftc Sources/TetherlineCore/*.swift Tests/ControlProbe/Client.swift -o "$base/client"
swiftc Sources/TetherlineCore/*.swift Tests/ControlProbe/Generate.swift -o "$base/generate"
for executable in engine controller client; do codesign --force --sign - "$base/$executable"; done
if [[ " $* " == *" --install-production "* ]]; then
    codesign --verify --deep --strict build/Tetherline.app
    "$base/generate" "$base" "$base/test.sh" "$PWD/build/Tetherline.app"
else
    "$base/generate" "$base" "$base/test.sh"
fi
/bin/sh -n "$base/test.sh"
if [[ " $* " == *" --prepare-only "* ]]; then
    echo "$base/test.sh"
    exit 0
fi
# The script text, not its path, goes to the prompt: later edits cannot change what runs as root.
python3 - "$base/test.sh" <<'PY'
import pathlib, subprocess, sys
script = pathlib.Path(sys.argv[1]).read_text()
literal = script.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
result = subprocess.run(['/usr/bin/osascript', '-e', 'do shell script "' + literal + '" with administrator privileges'],
                        text=True, capture_output=True)
print(result.stdout, end='')
print(result.stderr, end='')
raise SystemExit(result.returncode)
PY
