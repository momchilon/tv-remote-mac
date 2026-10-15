#!/usr/bin/env python3
"""Build a standalone native .app. No installs or third-party packages."""
import pathlib
import plistlib
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(['swift', 'build', '-c', 'release', '--product', 'NotchRemote'], cwd=root, check=True)
bindir = pathlib.Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=root, text=True).strip())
app = root / 'dist' / 'Notch Remote.app'
# Recreate only this generated bundle; stale files must never reach a release.
if app.is_symlink():
    raise SystemExit('Refusing to replace a symlinked app bundle')
if app.exists():
    shutil.rmtree(app)
macos = app / 'Contents' / 'MacOS'
macos.mkdir(parents=True, exist_ok=True)
shutil.copy2(bindir / 'NotchRemote', macos / 'NotchRemote')
# Remove debug/local symbols (including checkout paths) from the distributed copy.
# The app is signed again after packaging; the installed app is never modified.
subprocess.run(['strip', '-S', '-x', str(macos / 'NotchRemote')], check=True)
info = {
    'CFBundleName': 'Notch Remote',
    'CFBundleDisplayName': 'Notch Remote',
    'CFBundleIdentifier': 'local.notchremote.app',
    'CFBundleExecutable': 'NotchRemote',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': (root / 'VERSION').read_text().strip(),
    'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '13.0',
    'LSUIElement': True,
    'LSMultipleInstancesProhibited': True,
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
    'NSLocalNetworkUsageDescription': 'Connect directly to your Samsung TV on your local network.',
    'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
}
resources = app / 'Contents' / 'Resources'
resources.mkdir(parents=True, exist_ok=True)
iconset = root / '.build' / 'NotchRemote.iconset'
subprocess.run(['swift', str(root / 'tools' / 'make-icon.swift'), str(iconset)], check=True)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'NotchRemote.icns')], check=True)
info['CFBundleIconFile'] = 'NotchRemote.icns'
with (app / 'Contents' / 'Info.plist').open('wb') as f:
    plistlib.dump(info, f)
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
print(app)
