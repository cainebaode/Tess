#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Tess/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Tess/Info.plist)
output="$task_root/.build/local/${version}-build${build}/development"
mkdir -p "$output" .build/cache
extra_settings=()
if [[ "${TESS_INTERNAL_CHECKS:-0}" == "1" ]]; then
  extra_settings+=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) TESS_INTERNAL_CHECKS')
fi
xcrun swift -module-cache-path .build/cache/SwiftModuleCache scripts/make-icon.swift \
  assets/branding/tess-spirit/tess-mascot.png Tess/Resources .build/cache/Tess.iconset \
  assets/branding/tess-spirit
iconutil -c icns .build/cache/Tess.iconset -o Tess/Resources/Tess.icns
xcodebuild -project Tess/Tess.xcodeproj -scheme Tess -configuration Release \
  -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath .build/cache/DerivedData -clonedSourcePackagesDirPath .build/cache/SourcePackages \
  "${extra_settings[@]}" CODE_SIGNING_ALLOWED=NO build > "$output/build.log" 2>&1 || {
    python3 -c 'from pathlib import Path; import sys; lines=Path(sys.argv[1]).read_text().splitlines(); errors=[line for line in lines if "error:" in line]; print("\n".join(line[:500] for line in (errors[-8:] or lines[-8:])))' "$output/build.log"
    exit 1
  }
# Replace only generated output so removed resources cannot survive an update.
rm -rf "$output/Tess.app"
ditto .build/cache/DerivedData/Build/Products/Release/Tess.app "$output/Tess.app"
if [[ -n "${TESS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$TESS_SIGNING_IDENTITY" \
    --entitlements Tess/Tess.entitlements "$output/Tess.app"
else
  codesign --force --sign - --entitlements Tess/Tess.entitlements "$output/Tess.app"
fi
codesign --verify --deep --strict "$output/Tess.app"
ditto -c -k --sequesterRsrc --keepParent "$output/Tess.app" "$output/Tess-${version}-build${build}.zip"
print "Built: $output/Tess.app"
