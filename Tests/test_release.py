#!/usr/bin/env python3
"""Public-release policy checks: file-only, no UI or live TV access."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ReleasePolicyTests(unittest.TestCase):
    def test_version_is_v02(self):
        self.assertEqual((ROOT / 'VERSION').read_text().strip(), '0.2')

    def test_release_docs_match_version_and_features(self):
        readme = (ROOT / 'README.md').read_text()
        self.assertIn('releases/download/v0.2/TV-Remote-v0.2-arm64.dmg', readme)
        self.assertNotIn('(unreleased)', readme)
        notes = ROOT / 'docs' / 'releases' / 'v0.2.md'
        self.assertTrue(notes.is_file())
        text = notes.read_text()
        for required in ['Find TVs', 'Multiple remotes', 'Samsung', 'Apple silicon', 'not Apple-notarized', 'SHA256SUMS']:
            self.assertIn(required, text)

    def test_ui_suites_are_explicitly_opt_in(self):
        for name in ['MenuBarControllerTests.swift', 'PanelViewTests.swift']:
            text = (ROOT / 'Tests' / 'NotchUITests' / name).read_text()
            self.assertIn('RUN_UI_TESTS', text, name)
            self.assertIn('XCTSkipUnless', text, name)

    def test_build_and_packaging_are_not_tied_to_a_home_directory(self):
        for root in [ROOT / 'Sources', ROOT / 'tools', ROOT / 'RemoteKit' / 'Sources']:
            for path in root.rglob('*'):
                if path.is_file() and path.suffix in {'.swift', '.py'}:
                    text = path.read_text()
                    self.assertNotRegex(text, r'/Users/[^/]+/', str(path))
                    self.assertNotIn('.hermes', text, str(path))
                    self.assertNotIn('hermes-tv', text, str(path))

    def test_open_source_license_and_tv_support_requests_are_documented(self):
        license_text = (ROOT / 'LICENSE').read_text() if (ROOT / 'LICENSE').exists() else ''
        self.assertIn('MIT License', license_text)
        readme = (ROOT / 'README.md').read_text()
        self.assertIn('Samsung only', readme)
        self.assertIn('any TV brand', readme)
        self.assertTrue((ROOT / '.github' / 'ISSUE_TEMPLATE' / 'tv-support.yml').is_file())

if __name__ == '__main__':
    unittest.main(verbosity=2)
