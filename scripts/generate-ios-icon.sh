#!/bin/sh
# Keep the original logo untouched; reduce only iOS artwork to 90% on white.
set -eu
cd "$(dirname "$0")/.."
sips --resampleHeightWidth 922 922 assets/icons/app_icon.png --out assets/icons/app_icon_ios.png >/dev/null
sips --padToHeightWidth 1024 1024 --padColor FFFFFF assets/icons/app_icon_ios.png >/dev/null
