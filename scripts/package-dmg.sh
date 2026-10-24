#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
app_path="${1:-dist/Tess.app}"
identity="${TESS_SIGNING_IDENTITY:?Set the Developer ID Application signing identity}"
[[ -d "$app_path" ]] || { print -u2 "App not found: $app_path"; exit 1; }
codesign --verify --deep --strict "$app_path"
signing_info=$(codesign -dv --verbose=4 "$app_path" 2>&1)
[[ "$signing_info" == *'Authority=Developer ID Application:'* ]]
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
stage="$task_root/.build/dmg-stage"
[[ "$stage" == "$task_root/.build/dmg-stage" ]] || exit 1
rm -rf "$stage"
mkdir -p "$stage" dist
ditto "$app_path" "$stage/Tess.app"
chmod -R a+rX "$stage/Tess.app"
codesign --verify --deep --strict "$stage/Tess.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Tess" -srcfolder "$stage" -format UDZO -ov "dist/Tess-${version}-arm64.dmg"
codesign --force --timestamp --sign "$identity" "dist/Tess-${version}-arm64.dmg"
hdiutil verify "dist/Tess-${version}-arm64.dmg"
shasum -a 256 "dist/Tess-${version}-arm64.dmg" > "dist/Tess-${version}-arm64.dmg.sha256"
print "Packaged: $task_root/dist/Tess-${version}-arm64.dmg"
