#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
identity="${TESS_SIGNING_IDENTITY:-Developer ID Application: Caine Chen (9D6XC2T2G5)}"
model_folder="${TESS_RELEASE_MODEL_DIRECTORY:-$task_root/.build/release-models/qwenSmall}"
[[ -f "$model_folder/.tess-verified.json" ]] || { print -u2 'A verified base speech model is required for the offline release.'; exit 1; }
python3 - "$model_folder" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);receipt=json.loads((root/'.tess-verified.json').read_text())
assert receipt['repository']=='aufklarer/Qwen3-ASR-0.6B-MLX-4bit'
for file in receipt['files']:
 path=(root/file['path']).resolve()
 assert path.is_relative_to(root.resolve()) and path.stat().st_size==file['size']
 digest=hashlib.sha256() if len(file['digest'])==64 else hashlib.sha1()
 if len(file['digest'])!=64: digest.update(('blob '+str(file['size'])+'\0').encode())
 with path.open('rb') as source:
  for chunk in iter(lambda:source.read(4*1024*1024),b''): digest.update(chunk)
 assert digest.hexdigest()==file['digest'],file['path']
print('Base speech model hashes verified:',receipt['revision'])
PY
mkdir -p .build
xcrun swift -module-cache-path .build/SwiftModuleCache scripts/make-icon.swift \
  assets/branding/tess-spirit/tess-mascot.png Tess/Resources .build/Tess.iconset \
  assets/branding/tess-spirit
iconutil -c icns .build/Tess.iconset -o Tess/Resources/Tess.icns
xcodebuild -project Tess/Tess.xcodeproj -scheme Tess -configuration Release \
  -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages \
  -archivePath .build/Tess-0.2.0.xcarchive CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=$identity" DEVELOPMENT_TEAM=9D6XC2T2G5 ENABLE_HARDENED_RUNTIME=YES archive
archive_app="$task_root/.build/Tess-0.2.0.xcarchive/Products/Applications/Tess.app"
ditto "$model_folder" "$archive_app/Contents/Resources/BaseSpeechModel.tessmodel"
chmod -R a+rX "$archive_app/Contents/Resources/BaseSpeechModel.tessmodel"
codesign --force --options runtime --timestamp --entitlements Tess/Tess.entitlements --sign "$identity" "$archive_app"
codesign --verify --deep --strict "$archive_app"
print "Release archive prepared with offline speech model: $archive_app"
