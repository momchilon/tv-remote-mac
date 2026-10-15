#!/usr/bin/env python3
"""Validate the built bundle without sending commands to a television."""
import pathlib
import plistlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = pathlib.Path(sys.argv.pop(1)) if len(sys.argv) > 1 and sys.argv[1].endswith('.app') else ROOT / 'dist' / 'Notch Remote.app'

class BundleTests(unittest.TestCase):
    def test_bundle_contains_only_release_files(self):
        expected = {
            'Contents/Info.plist',
            'Contents/MacOS/NotchRemote',
            'Contents/Resources/NotchRemote.icns',
            'Contents/_CodeSignature/CodeResources',
        }
        actual = {str(p.relative_to(APP)) for p in APP.rglob('*') if p.is_file()}
        self.assertEqual(actual, expected, 'Unexpected or missing files in the release app')

    def test_native_accessory_bundle_has_no_cloud_or_global_tls_bypass(self):
        info = APP / 'Contents' / 'Info.plist'
        self.assertTrue(info.is_file(), 'Build the actual .app first')
        with info.open('rb') as stream:
            p = plistlib.load(stream)
        self.assertEqual(p['CFBundleIdentifier'], 'local.notchremote.app')
        self.assertEqual(p['CFBundleShortVersionString'], (ROOT / 'VERSION').read_text().strip())
        self.assertEqual(p['CFBundleVersion'], '2')
        self.assertEqual(p['LSMinimumSystemVersion'], '13.0')
        self.assertIs(p['LSUIElement'], True)
        self.assertEqual(p['CFBundleExecutable'], 'NotchRemote')
        self.assertTrue(p['NSLocalNetworkUsageDescription'])
        ats = p.get('NSAppTransportSecurity', {})
        self.assertNotIn('NSAllowsArbitraryLoads', ats)
        self.assertTrue(ats.get('NSAllowsLocalNetworking'))
        binary = APP / 'Contents' / 'MacOS' / p['CFBundleExecutable']
        self.assertTrue(binary.is_file())
        self.assertFalse(str(ROOT).encode() in binary.read_bytes(), 'Release binary embeds its local checkout path')
        result = subprocess.run(['codesign', '--verify', '--strict', str(APP)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
        self.assertNotIn('/opt/homebrew/', linked)
        self.assertNotIn('/Users/', '\n'.join(linked.splitlines()[1:]))

if __name__ == '__main__':
    unittest.main(verbosity=2)
