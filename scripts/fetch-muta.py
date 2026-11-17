#!/usr/bin/env python3
"""Fetch pinned upstream artifacts; no source patches, no upstream installer."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def verified_download(url, path, expected):
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == expected:
        return
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        staging = Path(f.name)
    try:
        subprocess.run(["/usr/bin/curl", "--fail", "--location", "--silent", "--show-error",
                        "--proto", "=https", "--tlsv1.2", url, "-o", str(staging)], check=True)
        actual = hashlib.sha256(staging.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"Błędna SHA-256: {url}\nOczekiwana: {expected}\nOtrzymana: {actual}")
        staging.replace(path)
    finally:
        staging.unlink(missing_ok=True)


def main():
    pin = json.loads((ROOT / "Vendor/muta.version").read_text())
    tag = pin["tag"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?", tag):
        raise ValueError("Nieprawidłowy tag")
    for key in ("sha256", "licenseSHA256"):
        if not re.fullmatch(r"[a-f0-9]{64}", pin[key]):
            raise ValueError(f"Nieprawidłowa suma: {key}")
    cache = ROOT / ".build/vendor" / tag
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "muta.tar.gz"
    verified_download(f"https://github.com/jost-s/macos-usb-tether-android/releases/download/{tag}/muta-universal-apple-darwin.tar.gz", archive, pin["sha256"])
    verified_download(f"https://raw.githubusercontent.com/jost-s/macos-usb-tether-android/{tag}/LICENSE", cache / "LICENSE", pin["licenseSHA256"])
    with tarfile.open(archive) as tar:
        candidates = [m for m in tar.getmembers() if Path(m.name).name == "muta" and m.isfile()]
        if len(candidates) != 1:
            raise ValueError("Archiwum nie zawiera jednej zwykłej binarki muta")
        # Do not extract paths, links or other archive entries.
        (cache / "muta").write_bytes(tar.extractfile(candidates[0]).read())
    os.chmod(cache / "muta", 0o755)
    print(cache)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        sys.exit(str(error))

