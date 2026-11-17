#!/bin/bash
set -euo pipefail
identities=$(/usr/bin/security find-identity -v -p codesigning)
printf '%s\n' "$identities"
if ! printf '%s\n' "$identities" | /usr/bin/grep -q '"Apple Development:'; then
    echo 'Brak ważnego Apple Development z kluczem prywatnym. Xcode → Settings → Accounts → Manage Certificates → + → Apple Development.' >&2
    exit 1
fi

