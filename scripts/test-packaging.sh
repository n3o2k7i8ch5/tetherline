#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint Resources/Info.plist Resources/pl.tetherline.muta.plist
python3 -m unittest discover -s Tests/Packaging -v

