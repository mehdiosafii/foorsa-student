#!/usr/bin/env python3
"""Makes the Foorsa CRM app's icons and launch image from store/.

  python3 tool/make_icons.py

- store/app-icon-1024.png: the white Foorsa mark on navy, the iPhone, iPad
  and Android icon (no transparency: Apple refuses an icon with alpha).
- store/app-icon-maskable-1024.png: the same with more room round the mark,
  for Android's adaptive icon and the web app's maskable icon, which crop a
  circle or a squircle out of it.
- assets/mark-white.png: the mark alone, for the launch and loading screens.

Run it again after changing either picture; it overwrites what it makes.
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON = Image.open(ROOT / 'store' / 'app-icon-1024.png').convert('RGB')
MASKABLE = Image.open(ROOT / 'store' / 'app-icon-maskable-1024.png').convert('RGB')
MARK = Image.open(ROOT / 'assets' / 'mark-white.png').convert('RGBA')
NAVY = (4, 18, 41)


def ios():
    folder = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    contents = json.loads((folder / 'Contents.json').read_text())
    for image in contents['images']:
        name = image.get('filename')
        if not name:
            continue
        points = float(image['size'].split('x')[0])
        scale = int(image['scale'].rstrip('x'))
        px = round(points * scale)
        ICON.resize((px, px), Image.LANCZOS).save(folder / name)
    # The launch screen: the mark on navy (LaunchScreen.storyboard's colour).
    launch = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'LaunchImage.imageset'
    for scale, name in ((1, 'LaunchImage.png'), (2, 'LaunchImage@2x.png'), (3, 'LaunchImage@3x.png')):
        side = 88 * scale
        mark = MARK.copy()
        mark.thumbnail((side, side), Image.LANCZOS)
        canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
        canvas.alpha_composite(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
        canvas.save(launch / name)


def android():
    res = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for density, px in sizes.items():
        folder = res / f'mipmap-{density}'
        folder.mkdir(parents=True, exist_ok=True)
        ICON.resize((px, px), Image.LANCZOS).save(folder / 'ic_launcher.png')
        # Adaptive icon foreground: 108dp with the mark in the middle 72dp.
        fg_px = px * 108 // 48
        mark = MARK.copy()
        mark.thumbnail((round(fg_px * 0.42), round(fg_px * 0.42)), Image.LANCZOS)
        fg = Image.new('RGBA', (fg_px, fg_px), (0, 0, 0, 0))
        fg.alpha_composite(mark, ((fg_px - mark.width) // 2, (fg_px - mark.height) // 2))
        fg.save(folder / 'ic_launcher_foreground.png')
    anydpi = res / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    values = res / 'values'
    values.mkdir(parents=True, exist_ok=True)
    (values / 'colors.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#041229</color>\n'
        '    <color name="launch_background">#041229</color>\n'
        '</resources>\n')
    # The launch screen's mark.
    drawable = res / 'drawable-nodpi'
    drawable.mkdir(parents=True, exist_ok=True)
    mark = MARK.copy()
    mark.thumbnail((288, 288), Image.LANCZOS)
    mark.save(drawable / 'launch_mark.png')


def web():
    out = ROOT / 'store' / 'web'
    out.mkdir(parents=True, exist_ok=True)
    for px in (192, 512):
        ICON.resize((px, px), Image.LANCZOS).save(out / f'crm-icon-{px}.png')
        MASKABLE.resize((px, px), Image.LANCZOS).save(out / f'crm-icon-maskable-{px}.png')
    ICON.resize((180, 180), Image.LANCZOS).save(out / 'crm-apple-touch-icon.png')


if __name__ == '__main__':
    ios()
    android()
    web()
    print('icons made')
