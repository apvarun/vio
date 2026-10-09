import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("assets", Path(__file__).parents[2] / "Scripts/assets.py")
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)


class AssetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Scripts").mkdir()
        self.target = self.root / "model.cact"
        self.target.write_bytes(b"original")
        manifest = [{"path": "model.cact", "url": "https://example.invalid/model", "sha256": assets.digest(self.target)}]
        (self.root / "Scripts/assets.json").write_text(json.dumps(manifest))

    def run_command(self, command):
        with patch.object(assets, "ROOT", self.root), patch("sys.argv", ["assets.py", command]):
            assets.main()

    def test_verify_rejects_missing_or_changed_asset(self):
        self.run_command("verify")
        self.target.write_bytes(b"changed")
        with self.assertRaises(SystemExit) as error:
            self.run_command("verify")
        self.assertEqual(error.exception.code, 1)
        self.target.unlink()
        with self.assertRaises(SystemExit):
            self.run_command("verify")

    def test_download_reuses_valid_asset_without_network(self):
        with patch.object(assets.urllib.request, "urlopen") as request:
            self.run_command("download")
            request.assert_not_called()

    def test_failed_download_preserves_existing_asset(self):
        import io
        self.target.write_bytes(b"keep this")
        for response in [io.BytesIO(b"bad download"), OSError("HTTP failure")]:
            with self.subTest(response=response):
                kwargs = {"side_effect": response} if isinstance(response, Exception) else {"return_value": response}
                with patch.object(assets.urllib.request, "urlopen", **kwargs):
                    with self.assertRaises(SystemExit):
                        self.run_command("download")
                self.assertEqual(self.target.read_bytes(), b"keep this")
                self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["Scripts", "model.cact"])

    def test_download_replaces_asset_after_verification(self):
        import io
        self.target.unlink()
        with patch.object(assets.urllib.request, "urlopen", return_value=io.BytesIO(b"original")):
            self.run_command("download")
        self.assertEqual(self.target.read_bytes(), b"original")
