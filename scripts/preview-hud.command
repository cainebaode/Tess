#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_root/Tess/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$task_root/Tess/Info.plist")
exec "$task_root/.build/local/${version}-build${build}/development/Tess.app/Contents/MacOS/Tess" --hud-preview
