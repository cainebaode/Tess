#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
# Execute the actual service and receipt validator with only the model loader
# replaced by a deterministic failing actor. No weights, network, or user state.
python3 - <<'PY'
from pathlib import Path
source = Path("Tess/Sources/ASRService.swift").read_text()
source = source.replace("@preconcurrency import Qwen3ASR\n", "").replace("import WhisperASR\n", "")
start = source.index("private actor ASRRuntime {")
end = source.index("private final class TranscriptionWait:", start)
source = source[:start] + '''
private enum InjectedLoadError: Error { case failed }
private actor ASRRuntime {
    func prepare(model: ASRModel, directory: URL) throws { throw InjectedLoadError.failed }
    func unload() {}
    func transcribe(_ samples: [Float], model: ASRModel, language: String?) throws -> String { throw InjectedLoadError.failed }
}
''' + source[end:]
source += '''
@main struct ASRRecoveryCheck {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TessASRRecovery-" + UUID().uuidString)
        let folder = root.appendingPathComponent("qwenSmall")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["config.json", "vocab.json", "merges.txt", "tokenizer_config.json", "model.safetensors"]
        var files: [ModelReceipt.File] = []
        for name in names {
            let file = folder.appendingPathComponent(name)
            try Data("test-only".utf8).write(to: file)
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            files.append(.init(path: name, size: 9, digest: "isolated-test", modificationDate: attrs[.modificationDate] as! Date,
                               sourceRepository: ASRModel.qwenSmall.repository, sourceRevision: "isolated-test"))
        }
        try ModelReceipt(repository: ASRModel.qwenSmall.repository, revision: "isolated-test",
                         runtime: "speech-swift cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa", files: files).save(to: folder)
        let service = ASRService(modelsDirectory: root)
        precondition(service.isReady(.qwenSmall), "Verified fixture must start ready")
        for _ in 0..<2 {
            do {
                try await service.prepare(model: .qwenSmall)
                fatalError("Injected loader must fail")
            } catch InjectedLoadError.failed {
                guard case .failed = service.states[.qwenSmall] else { fatalError("Failure remains visible") }
                precondition(service.isReady(.qwenSmall), "Valid files must permit another load attempt")
            }
        }
        try Data("changed".utf8).write(to: folder.appendingPathComponent("config.json"))
        precondition(!service.isReady(.qwenSmall), "Changed files must invalidate readiness")
        do {
            try await service.prepare(model: .qwenSmall)
            fatalError("Invalid files must not reach runtime")
        } catch ASRError.modelNotReady { }
        print("ASR recovery passed: two load failures remain retryable; changed files block preparation.")
    }
}
'''
Path(".build/verification/checks/ASRRecoveryCheck.swift").write_text(source)
PY
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  Tess/Sources/AudioLevelMeter.swift Tess/Sources/AudioRecorder.swift .build/verification/checks/ASRRecoveryCheck.swift -o .build/verification/checks/asr-recovery-check
.build/verification/checks/asr-recovery-check
