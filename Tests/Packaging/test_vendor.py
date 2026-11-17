import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("vendor", ROOT / "scripts/fetch-muta.py")
vendor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vendor)


class PackagingTests(unittest.TestCase):
    def test_bad_download_never_replaces_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "muta.tar.gz"
            target.write_bytes(b"previous cache")

            def download(arguments, **kwargs):
                Path(arguments[-1]).write_bytes(b"tampered binary")

            with patch.object(vendor.subprocess, "run", side_effect=download):
                with self.assertRaisesRegex(ValueError, "SHA-256"):
                    vendor.verified_download("https://example.invalid/release", target, "0" * 64)
            self.assertEqual(target.read_bytes(), b"previous cache")
            self.assertEqual(len(list(Path(directory).iterdir())), 1)

    def test_verified_cache_needs_no_network(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "muta.tar.gz"
            target.write_bytes(b"verified archive")
            with patch.object(vendor.subprocess, "run") as download:
                vendor.verified_download("https://example.invalid/release", target,
                                         hashlib.sha256(target.read_bytes()).hexdigest())
                download.assert_not_called()

    def test_launchd_runs_protected_engine_with_unthrottled_lifecycle(self):
        with (ROOT / "Resources/pl.tetherline.muta.plist").open("rb") as f:
            daemon = plistlib.load(f)
        self.assertNotIn("BundleProgram", daemon)
        self.assertEqual(daemon["ProgramArguments"], ["/Library/Application Support/Tetherline/muta", "run"])
        self.assertEqual(daemon["AssociatedBundleIdentifiers"], ["pl.tetherline.app"])
        self.assertTrue(daemon["KeepAlive"])
        self.assertTrue(daemon["RunAtLoad"])
        self.assertEqual(daemon["ProcessType"], "Standard")
        self.assertNotIn("Program", daemon)
        self.assertEqual(daemon["StandardOutPath"], daemon["StandardErrorPath"])

    def test_menu_agent_is_not_dock_app(self):
        with (ROOT / "Resources/Info.plist").open("rb") as f:
            self.assertTrue(plistlib.load(f)["LSUIElement"])


if __name__ == "__main__":
    unittest.main()
