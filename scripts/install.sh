#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
target=/Applications/Tetherline.app
if [[ -e "$target" ]]; then
    echo 'Tetherline już istnieje. Zakończ interfejs i zastąp paczkę z build/Tetherline.app. Aby zaktualizować chroniony silnik, wyłącz i włącz tethering w nowej aplikacji.' >&2
    exit 1
fi
codesign --verify --deep --strict build/Tetherline.app
ditto build/Tetherline.app "$target"
open "$target"

