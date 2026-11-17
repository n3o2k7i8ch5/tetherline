#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:?Użycie: scripts/bump-muta.sh v0.1.5}
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][a-zA-Z0-9.-]+)?$ ]] || { echo 'Nieprawidłowy tag' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/jost-s/macos-usb-tether-android/releases/download/$tag"
archive=muta-universal-apple-darwin.tar.gz
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "$base/$archive" -o "$tmp/$archive"
sha=$(shasum -a 256 "$tmp/$archive" | awk '{print $1}')
code=$(curl --location --silent --show-error --proto '=https' --tlsv1.2 -w '%{http_code}' "$base/muta-universal-apple-darwin.sha256" -o "$tmp/checksum")
if [[ "$code" == 200 ]]; then
    published=$(awk 'NR == 1 {print $1}' "$tmp/checksum")
    [[ "$sha" == "$published" ]] || { echo 'Suma wydawcy nie zgadza się!' >&2; exit 1; }
elif [[ "$code" != 404 ]]; then
    echo "Nie udało się sprawdzić sumy wydawcy (HTTP $code)." >&2; exit 1
else
    echo 'Wydawca nie publikuje sumy; zapisuję lokalnie obliczoną SHA-256.' >&2
fi
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 "https://raw.githubusercontent.com/jost-s/macos-usb-tether-android/$tag/LICENSE" -o "$tmp/LICENSE"
license_sha=$(shasum -a 256 "$tmp/LICENSE" | awk '{print $1}')
mkdir -p Vendor
# JSON, never sourced as shell code. One atomic update pins both artifacts.
printf '{\n  "tag": "%s",\n  "sha256": "%s",\n  "licenseSHA256": "%s"\n}\n' "$tag" "$sha" "$license_sha" > Vendor/muta.version.new
mv Vendor/muta.version.new Vendor/muta.version
echo "Przypięto muta $tag ($sha)"

