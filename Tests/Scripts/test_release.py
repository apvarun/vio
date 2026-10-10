"""Exercise release failures without Apple credentials or network submissions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'Scripts').mkdir()
        shutil.copy(ROOT / 'Scripts/build-dmg.sh', self.root / 'Scripts')
        resources = self.root / 'Resources/DMG'
        resources.mkdir(parents=True)
        shutil.copy(ROOT / 'Resources/DMG/release.entitlements', resources)
        (resources / 'background.tiff').touch()
        app = self.root / 'build/Vio.app/Contents'
        app.mkdir(parents=True)
        shutil.copy(ROOT / 'Info.plist', app)
        (self.root / 'build/Vio.icns').touch()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}')
        self.env.pop('SIGNING_IDENTITY', None)
        self.env.pop('NOTARY_PROFILE', None)
        self.env['MOCK_LOG'] = str(self.root / 'calls')
        self.env['MOCK_STATUS'] = 'Accepted'
        self.command('uname', 'echo arm64')
        self.command('codesign', ':')
        self.command('spctl', ':')
        self.command('hdiutil', ':')
        self.command('create-dmg', 'for last; do :; done\nargs=("$@")\nprintf dmg > "${args[${#args[@]}-2]}"')
        self.command('ditto', '''if [[ "$1" == -c ]]; then
    for last; do :; done
    touch "$last"
else
    cp -R "$1" "$2"
fi''')
        self.command('xcrun', '''echo "$*" >> "$MOCK_LOG"
if [[ "$1 $2" == 'notarytool submit' ]]; then
    if [[ "$3" == *.dmg && "${MOCK_REJECT_DMG:-}" == 1 ]]; then MOCK_STATUS=Invalid; fi
    printf '{"status":"%s","id":"test-id"}\n' "$MOCK_STATUS"
elif [[ "$1 $2" == 'notarytool log' ]]; then
    for last; do :; done
    printf '{}' > "$last"
fi''')

    def command(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\nset -e\n' + body + '\n')
        path.chmod(0o755)

    def run_release(self, **env):
        return subprocess.run(['bash', str(self.root / 'Scripts/build-dmg.sh'), 'release'],
                              env=dict(self.env, **env), text=True, capture_output=True)

    def credentials(self):
        return dict(SIGNING_IDENTITY='Developer ID Application: Test (TEAM)', NOTARY_PROFILE='test')

    def test_missing_identity(self):
        result = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Set SIGNING_IDENTITY', result.stderr)

    def test_missing_notary_profile(self):
        result = self.run_release(SIGNING_IDENTITY=self.credentials()['SIGNING_IDENTITY'])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Set NOTARY_PROFILE', result.stderr)

    def test_wrong_certificate_type(self):
        result = self.run_release(SIGNING_IDENTITY='Apple Development: Test', NOTARY_PROFILE='test')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Developer ID Application certificate', result.stderr)

    def test_rejected_notarization_never_publishes(self):
        result = self.run_release(**self.credentials(), MOCK_STATUS='Invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Notarization rejected app', result.stderr)
        self.assertEqual(list((self.root / 'build/releases').glob('*.dmg*')), [])
        self.assertEqual(list((self.root / 'build').glob('dmg.*')), [])
        self.assertNotIn('stapler staple', (self.root / 'calls').read_text())
        log = self.root / 'build/releases/Vio-0.1.0-app-notary.json'
        self.assertTrue(log.exists())

    def test_success_checks_both_artifacts_and_preserves_original(self):
        result = self.run_release(**self.credentials())
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.root / 'build/releases/Vio-0.1.0-arm64.dmg'
        self.assertTrue(output.exists())
        self.assertTrue(Path(str(output) + '.sha256').exists())
        checksum = subprocess.run(['shasum', '-a', '256', '-c', output.name + '.sha256'],
                                  cwd=output.parent, capture_output=True, text=True)
        self.assertEqual(checksum.returncode, 0, checksum.stderr)
        calls = (self.root / 'calls').read_text()
        self.assertEqual(calls.count('notarytool submit'), 2)
        self.assertEqual(calls.count('stapler staple'), 2)
        self.assertEqual(calls.count('stapler validate'), 2)
        self.assertTrue((self.root / 'build/Vio.app/Contents/Info.plist').exists())
        second = self.run_release(**self.credentials())
        self.assertNotEqual(second.returncode, 0)
        self.assertIn('Output exists', second.stderr)
        self.assertEqual(output.read_bytes(), b'dmg')

    def test_rejected_dmg_never_publishes(self):
        result = self.run_release(**self.credentials(), MOCK_REJECT_DMG='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Notarization rejected dmg', result.stderr)
        self.assertEqual(list((self.root / 'build/releases').glob('*.dmg*')), [])
        self.assertEqual((self.root / 'calls').read_text().count('stapler staple'), 1)

    def test_preview_needs_no_credentials(self):
        result = subprocess.run(['bash', str(self.root / 'Scripts/build-dmg.sh'), 'preview'],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Preview only', result.stdout)
        self.assertFalse((self.root / 'calls').exists())
        self.assertTrue((self.root / 'build/releases/Vio-0.1.0-arm64.dmg').exists())
