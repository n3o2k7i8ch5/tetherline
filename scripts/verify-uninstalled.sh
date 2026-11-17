#!/bin/bash
# Read-only audit. Run after quitting the app and emptying its Trash entry.
set -uo pipefail
remaining=0
for path in \
    /Applications/Tetherline.app \
    /Library/Logs/Tetherline \
    "/Library/Application Support/Tetherline" \
    /Library/LaunchDaemons/pl.tetherline.muta.plist \
    /Library/LaunchDaemons/pl.tetherline.control.plist \
    "$HOME/Library/LaunchAgents/pl.tetherline.app.plist" \
    "$HOME/Library/Preferences/pl.tetherline.app.plist" \
    "$HOME/Library/Caches/pl.tetherline.app" \
    "$HOME/Library/Saved Application State/pl.tetherline.app.savedState"; do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "POZOSTAŁO: $path"
        remaining=1
    fi
done
for label in system/pl.tetherline.muta system/pl.tetherline.control "gui/$(id -u)/pl.tetherline.app"; do
    if launchctl print "$label" >/dev/null 2>&1; then
        echo "POZOSTAŁO: $label"
        remaining=1
    fi
done
if /usr/bin/pgrep -x Tetherline >/dev/null; then
    echo 'POZOSTAŁO: proces Tetherline'
    remaining=1
fi
if /usr/bin/pgrep -x TetherlineControl >/dev/null; then
    echo 'POZOSTAŁO: proces TetherlineControl'
    remaining=1
fi
if [[ -e /var/run/muta.sock ]]; then
    echo 'UWAGA: /var/run/muta.sock istnieje (może należeć do osobnej instalacji muty).'
fi
if [[ "$remaining" == 0 ]]; then
    echo 'Brak wskazanych plików i załadowanych usług Tetherline. Sprawdź też Kosz i panel Rzeczy otwierane podczas logowania.'
fi
exit "$remaining"
