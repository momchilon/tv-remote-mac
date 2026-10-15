#!/usr/bin/env python3
"""Package the verified app without personal settings or desktop automation."""
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'dist' / 'Notch Remote.app'
IMAGE = ROOT / 'dist' / 'TV Remote.dmg'
SCRATCH = pathlib.Path(tempfile.gettempdir())

subprocess.run([sys.executable, str(ROOT / 'Tests' / 'verify_bundle.py'), str(APP)], check=True)
SCRATCH.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='tv-remote-dmg-', dir=SCRATCH) as temporary:
    stage = pathlib.Path(temporary)
    shutil.copytree(APP, stage / APP.name, symlinks=True)
    (stage / 'Applications').symlink_to('/Applications')
    (stage / 'Install.txt').write_text(
        'TV Remote for Mac\n\n'
        '1. Drag Notch Remote.app onto the Applications folder.\n'
        '2. Eject this disk image.\n'
        '3. Open Notch Remote from Applications.\n'
        '4. Click the remote-shaped icon in the menu bar.\n\n'
        'Apple silicon Macs; macOS 13 or later.\n'
        'No Dock icon. The controls appear only when you click the menu-bar icon.\n'
        'The original app name is retained to preserve existing preferences.\n\n'
        'On a new Mac, enter your Samsung TV IP address in Connection settings\n'
        'and choose Allow on the TV. No personal TV pairing data is included.\n\n'
        'This personal build is ad-hoc signed but not notarized by Apple.\n'
        'Another Mac may require manual approval in Privacy & Security before opening it.\n',
        encoding='utf-8')
    if IMAGE.exists():
        IMAGE.unlink()
    modern = subprocess.run(['diskutil', 'image', 'create', 'from', '--help'],
                            capture_output=True, text=True)
    if modern.returncode == 0 and '--volumeName' in modern.stdout:
        command = ['diskutil', 'image', 'create', 'from', '--format', 'UDZO',
                   '--volumeName', 'TV Remote', str(stage), str(IMAGE)]
    else:
        command = ['hdiutil', 'create', '-volname', 'TV Remote', '-srcfolder',
                   str(stage), '-fs', 'HFS+', '-format', 'UDZO',
                   '-imagekey', 'zlib-level=9', str(IMAGE)]
    subprocess.run(command, check=True)
print(f'DMG: {IMAGE}')
print(f'Size: {IMAGE.stat().st_size:,} bytes ({IMAGE.stat().st_size / 1_000_000:.2f} MB)')
