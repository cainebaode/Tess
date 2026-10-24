#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Tess/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Tess/Info.plist)
app_path="${1:-${TESS_RELEASE_ROOT:-$task_root/.build/releases/${version}-build${build}}/notarized/Tess.app}"
identity="${TESS_SIGNING_IDENTITY:?Set the Developer ID Application signing identity}"
[[ -d "$app_path" ]] || { print -u2 "App not found: $app_path"; exit 1; }
codesign --verify --deep --strict "$app_path"
signing_info=$(codesign -dv --verbose=4 "$app_path" 2>&1)
[[ "$signing_info" == *'Authority=Developer ID Application:'* ]]
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
release_root="${TESS_RELEASE_ROOT:-$task_root/.build/releases/${version}-build${build}}"
output="${TESS_DIST_DIRECTORY:-$task_root/dist/${version}-build${build}}"
stage="$release_root/stage/dmg"
[[ "$version" != */* && "$build" != */* ]] || exit 1
image="$output/Tess-${version}-build${build}-arm64.dmg"
[[ ! -e "$image" ]] || { print -u2 "DMG already exists; preserve it before repackaging: $image"; exit 1; }
rm -rf "$stage"
mkdir -p "$stage" "$output"
ditto "$app_path" "$stage/Tess.app"
chmod -R a+rX "$stage/Tess.app"
codesign --verify --deep --strict "$stage/Tess.app"
ln -s /Applications "$stage/Applications"
if [[ -f "$output/安装说明.txt" ]]; then
  cp "$output/安装说明.txt" "$stage/安装说明.txt"
fi
hdiutil create -volname "Tess" -srcfolder "$stage" -format UDZO "$image"
codesign --force --timestamp --sign "$identity" "$image"
hdiutil verify "$image"
(cd "$output" && shasum -a 256 "${image:t}" > "${image:t}.sha256")
print "Packaged: $image"
