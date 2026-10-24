#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
python3 - <<'PY'
from pathlib import Path
import plistlib
source=Path('Tess/Sources/ASRService.swift').read_text().replace('@preconcurrency import Qwen3ASR\n','').replace('import WhisperASR\n','')
a=source.index('private actor ASRRuntime {');b=source.index('private final class TranscriptionWait:',a)
source=source[:a]+'''private actor ASRRuntime {
 func prepare(model: ASRModel, directory: URL) async throws {}
 func unload() {}
 func transcribe(_ samples: [Float], model: ASRModel, language: String?) async throws -> String { "isolated" }
}
'''+source[b:]
audio=Path('Tess/Sources/AudioRecorder.swift').read_text()
source+=audio[audio.index('struct RecordedAudio:'):audio.index('struct AudioInputDevice:')]
source+='''
@main struct BundleCheck {
 @MainActor static func main() async throws {
  let resources=Bundle.main.resourceURL!
  let pack=resources.appendingPathComponent("BaseSpeechModel.tessmodel")
  let writable=FileManager.default.temporaryDirectory.appendingPathComponent("TessBundleCheck-"+UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:writable) }
  func fixture(_ folder:URL, oldDates:Bool) throws {
   try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   var files:[ModelReceipt.File]=[]
   for name in ["config.json","vocab.json","merges.txt","tokenizer_config.json","model.safetensors"] {
    let url=folder.appendingPathComponent(name)
    try Data("test-only".utf8).write(to:url)
    let date=try FileManager.default.attributesOfItem(atPath:url.path)[.modificationDate] as! Date
    files.append(.init(path:name,size:9,digest:"isolated",modificationDate:oldDates ? .distantPast : date,sourceRepository:ASRModel.qwenSmall.repository,sourceRevision:"fixture"))
   }
   try ModelReceipt(repository:ASRModel.qwenSmall.repository,revision:"fixture",runtime:"speech-swift cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa",files:files).save(to:folder)
  }
  try fixture(pack,oldDates:true)
  let bundled=ASRService(modelsDirectory:writable)
  precondition(bundled.isReady(.qwenSmall) && bundled.usesBundledModel(.qwenSmall))
  try await bundled.prepare()
  await bundled.unload()
  try bundled.delete(.qwenSmall)
  precondition(bundled.isReady(.qwenSmall) && FileManager.default.fileExists(atPath:pack.path))
  try fixture(writable.appendingPathComponent("qwenSmall"),oldDates:false)
  let preferred=ASRService(modelsDirectory:writable)
  precondition(preferred.isReady(.qwenSmall) && !preferred.usesBundledModel(.qwenSmall))
  try preferred.delete(.qwenSmall)
  precondition(preferred.isReady(.qwenSmall) && preferred.usesBundledModel(.qwenSmall))
  try FileManager.default.removeItem(at:pack.appendingPathComponent("vocab.json"))
  let incomplete=ASRService(modelsDirectory:writable)
  precondition(!incomplete.isReady(.qwenSmall))
  print("Bundled-model checks passed: timestamp rounding, loading, writable preference, safe deletion and incomplete-pack rejection. Runtime is an isolated substitute.")
 }
}
'''
Path('.build/verification/checks/BundleCheck.swift').write_text(source)
app=Path('.build/verification/checks/BundleCheck.app/Contents');(app/'MacOS').mkdir(parents=True,exist_ok=True);(app/'Resources').mkdir(exist_ok=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'life.baode.tess.bundlecheck','CFBundleExecutable':'BundleCheck','CFBundlePackageType':'APPL'}))
PY
xcrun swiftc -O -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache .build/verification/checks/BundleCheck.swift \
  -o .build/verification/checks/BundleCheck.app/Contents/MacOS/BundleCheck
.build/verification/checks/BundleCheck.app/Contents/MacOS/BundleCheck
