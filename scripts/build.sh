#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build dist
extra_settings=()
if [[ "${TESS_INTERNAL_CHECKS:-0}" == "1" ]]; then
  extra_settings+=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) TESS_INTERNAL_CHECKS')
fi
xcrun swift -module-cache-path .build/SwiftModuleCache scripts/make-icon.swift \
  assets/branding/tess-spirit/tess-mascot.png Tess/Resources .build/Tess.iconset \
  assets/branding/tess-spirit
iconutil -c icns .build/Tess.iconset -o Tess/Resources/Tess.icns
xcodebuild -project Tess/Tess.xcodeproj -scheme Tess -configuration Release \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages \
  "${extra_settings[@]}" CODE_SIGNING_ALLOWED=NO build > .build/build.log 2>&1 || {
    python3 -c 'from pathlib import Path; lines=Path(".build/build.log").read_text().splitlines(); errors=[line for line in lines if "error:" in line]; print("\n".join(line[:500] for line in (errors[-8:] or lines[-8:])))'
    exit 1
  }
# Replace only generated output so removed resources cannot survive an update.
rm -rf dist/Tess.app
ditto .build/DerivedData/Build/Products/Release/Tess.app dist/Tess.app
if [[ -n "${TESS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$TESS_SIGNING_IDENTITY" \
    --entitlements Tess/Tess.entitlements dist/Tess.app
else
  codesign --force --sign - --entitlements Tess/Tess.entitlements dist/Tess.app
fi
codesign --verify --deep --strict dist/Tess.app
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Tess.app/Contents/Info.plist)
ditto -c -k --sequesterRsrc --keepParent dist/Tess.app "dist/Tess-${version}.zip"
print "Built: $task_root/dist/Tess.app"
