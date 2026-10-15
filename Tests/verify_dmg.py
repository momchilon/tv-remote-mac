#!/usr/bin/env python3
"""Verify the actual compressed disk image, its contents and app signature."""
import os
import pathlib
import plistlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
IMAGE = pathlib.Path(sys.argv.pop(1)) if len(sys.argv) > 1 and sys.argv[1].endswith('.dmg') else ROOT / 'dist' / 'TV Remote.dmg'

class DiskImageTests(unittest.TestCase):
    def test_image_is_small_mountable_and_contains_only_installer_files(self):
        self.assertTrue(IMAGE.is_file(), 'Create the actual DMG first')
        self.assertLess(IMAGE.stat().st_size, 5 * 1024 * 1024, 'Keep this native remote under 5 MiB')
        subprocess.run(['hdiutil', 'verify', str(IMAGE)], check=True, stdout=subprocess.DEVNULL)
        raw = subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-plist', str(IMAGE)])
        data = plistlib.loads(raw)
        mounted = [x for x in data['system-entities'] if 'mount-point' in x]
        self.assertEqual(len(mounted), 1)
        volume = pathlib.Path(mounted[0]['mount-point'])
        try:
            visible = {p.name for p in volume.iterdir() if not p.name.startswith('.')}
            self.assertEqual(visible, {'Notch Remote.app', 'Applications', 'Install.txt'})
            self.assertTrue((volume / 'Applications').is_symlink())
            self.assertEqual(os.readlink(volume / 'Applications'), '/Applications')
            app = volume / 'Notch Remote.app'
            subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
            subprocess.run([sys.executable, str(ROOT / 'Tests' / 'verify_bundle.py'), str(app)], check=True)
            self.assertFalse(any(p.name in {'connections.json', 'token', '.token'} for p in app.rglob('*')))
            notes = (volume / 'Install.txt').read_text()
            self.assertIn('Applications', notes)
            self.assertIn('Apple silicon', notes)
            self.assertIn('not notarized', notes)
        finally:
            subprocess.run(['hdiutil', 'detach', str(volume)], check=True, stdout=subprocess.DEVNULL)

if __name__ == '__main__':
    unittest.main(verbosity=2)
