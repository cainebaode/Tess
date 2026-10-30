#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/verification/checks .build/cache/CheckModuleCache
# Real capture/service code with a deliberately slow, cancellation-ignoring
# model substitute. No microphone, network, model weights, or user preferences.
python3 - <<'PY'
from pathlib import Path
source = Path("Tess/Sources/ASRService.swift").read_text()
source = source.replace("@preconcurrency import Qwen3ASR\n", "").replace("import WhisperASR\n", "")
start = source.index("private actor ASRRuntime {")
end = source.index("private final class TranscriptionWait:", start)
source = source[:start] + '''
private actor ASRRuntime {
    static let probe = RuntimeProbe()
    func prepare(model: ASRModel, directory: URL) async throws {
        Self.probe.beginPreparation()
        await Task.detached { try? await Task.sleep(for: .milliseconds(120)) }.value
        Self.probe.end()
    }
    func unload() {}
    func transcribe(_ samples: [Float], model: ASRModel, language: String?, context: String?) async throws -> String {
        Self.probe.begin()
        await Task.detached { try? await Task.sleep(for: .milliseconds(120)) }.value
        Self.probe.end()
        return "transcript-\\(samples.count)"
    }
}
''' + source[end:]
source += '''
private final class RuntimeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var running = 0
    private var maximum = 0
    private var preparations = 0
    func beginPreparation() { lock.lock(); preparations += 1; running += 1; maximum = max(maximum, running); lock.unlock() }
    func begin() { lock.lock(); calls += 1; running += 1; maximum = max(maximum, running); lock.unlock() }
    func end() { lock.lock(); running -= 1; lock.unlock() }
    func status() -> (calls: Int, maximum: Int) { lock.lock(); defer { lock.unlock() }; return (calls, maximum) }
    func preparationCount() -> Int { lock.lock(); defer { lock.unlock() }; return preparations }
}
'''
source += Path("Tess/Sources/AudioRecorder.swift").read_text()
source += '''
@main struct LiveTranscriptionCheck {
    @MainActor static func main() async throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let capture = CaptureBuffer(converter: AVAudioConverter(from: format, to: format)!, targetFormat: format)
        func append(_ count: Int, value: Float) {
            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
            input.frameLength = AVAudioFrameCount(count)
            input.floatChannelData![0].update(repeating: value, count: count)
            capture.append(input)
        }
        append(16_000, value: 0)
        precondition(capture.snapshot(maximumSamples: 16_000) == nil, "Silence must not schedule inference")
        append(8_000, value: 0.03)
        precondition(capture.snapshot(maximumSamples: 16_000)?.count == 16_000)
        precondition(capture.snapshot(maximumSamples: 16_000) == nil, "Unchanged audio must not schedule inference")
        append(8_000, value: 0)
        _ = capture.snapshot(maximumSamples: 16_000) // The converter may flush the last spoken frames.
        append(8_000, value: 0)
        precondition(capture.snapshot(maximumSamples: 16_000) == nil, "Old speech must not be transcribed again during silence")
        append(16_000, value: 0.03)
        let bounded = capture.snapshot(maximumSamples: 16_000)!
        precondition(bounded.count == 16_000 && bounded.last == 0.03, "Preview must use the latest bounded audio")
        let firstChunk = capture.snapshot(maximumSamples: 16_000, startingAt: 0)!
        let secondChunk = capture.snapshot(maximumSamples: 16_000, startingAt: 16_000)!
        precondition(firstChunk.count == 16_000 && firstChunk.first == 0, "Fixed preview must retain the beginning, not just the tail")
        precondition(secondChunk.count == 16_000 && secondChunk.first == 0.03, "Next preview must start at its exact sample offset")
        precondition(capture.snapshot(maximumSamples: 16_000, startingAt: 100_000) == nil)
        let final = capture.finish()
        precondition(final.samples.count == 56_000 && final.hasSpeech, "Previews must preserve the entire final recording")
        precondition(capture.snapshot(maximumSamples: 16_000) == nil, "Stopped recording must not emit previews")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TessLiveCheck-" + UUID().uuidString)
        let folder = root.appendingPathComponent("qwenSmall")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var files: [ModelReceipt.File] = []
        for name in ["config.json", "vocab.json", "merges.txt", "tokenizer_config.json", "model.safetensors"] {
            let file = folder.appendingPathComponent(name)
            try Data("test-only".utf8).write(to: file)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            files.append(.init(path: name, size: 9, digest: "isolated-test", modificationDate: attributes[.modificationDate] as! Date,
                               sourceRepository: ASRModel.qwenSmall.repository, sourceRevision: "isolated-test"))
        }
        try ModelReceipt(repository: ASRModel.qwenSmall.repository, revision: "isolated-test",
                         runtime: "speech-swift cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa", files: files).save(to: folder)
        let service = ASRService(modelsDirectory: root)
        try await service.prepare()
        service.setRecording(true)
        let id = UUID()
        let audio = RecordedAudio(sessionID: id, samples: bounded, sampleRate: 16_000, hasSpeech: true)
        do {
            _ = try await service.transcribePartial(audio, sessionID: UUID())
            fatalError("Mismatched session must not run")
        } catch is CancellationError {}
        let partial = Task { try await service.transcribePartial(audio, sessionID: id) }
        while ASRRuntime.probe.status().calls == 0 { await Task.yield() }
        do {
            _ = try await service.transcribePartial(audio, sessionID: id)
            fatalError("A second preview must not enter the model concurrently")
        } catch ASRError.busy {}
        service.setRecording(false)
        let completeAudio = RecordedAudio(sessionID: id, samples: final.samples, sampleRate: 16_000, hasSpeech: true)
        let text = try await service.transcribe(completeAudio, sessionID: id)
        precondition(text == "transcript-56000", "Final recognition must receive the full audio")
        do {
            _ = try await partial.value
            fatalError("A cancelled preview must not expose a late result")
        } catch is CancellationError {}
        precondition(ASRRuntime.probe.status().maximum == 1, "Final and preview must never overlap")
        while service.isTranscribing { await Task.yield() }
        service.setRecording(true)
        let nextID = UUID()
        let next = try await service.transcribePartial(audio.withSessionID(nextID), sessionID: nextID)
        precondition(next == "transcript-16000", "A cancelled session must not break the next preview")
        service.setRecording(false)
        let preparationCount = ASRRuntime.probe.preparationCount()
        let oldPreparation = Task { try await service.prepare() }
        while ASRRuntime.probe.preparationCount() == preparationCount { await Task.yield() }
        do {
            try await service.prepare()
            fatalError("Uncancelled loading must remain busy")
        } catch ASRError.busy {}
        oldPreparation.cancel()
        service.cancel()
        let cancelledRestart = Task { try await service.prepare() }
        try await Task.sleep(for: .milliseconds(20))
        cancelledRestart.cancel()
        do {
            try await cancelledRestart.value
            fatalError("Waiting for old work must remain cancellable")
        } catch is CancellationError {}
        var restartFailures: [String] = []
        do { try await service.prepare() }
        catch ASRError.busy { restartFailures.append("cancelled loading") }
        do {
            try await oldPreparation.value
            fatalError("Cancelled preparation must not complete successfully")
        } catch is CancellationError {}
        let callCount = ASRRuntime.probe.status().calls
        let oldFinal = Task { try await service.transcribe(completeAudio, sessionID: id) }
        while ASRRuntime.probe.status().calls == callCount { await Task.yield() }
        oldFinal.cancel()
        service.cancel()
        do { try await service.prepare() }
        catch ASRError.busy { restartFailures.append("cancelled final") }
        do {
            _ = try await oldFinal.value
            fatalError("Cancelled final must not complete successfully")
        } catch is CancellationError {}
        while service.isTranscribing { await Task.yield() }
        precondition(ASRRuntime.probe.status().maximum == 1, "Rapid restart must not overlap loading or inference")
        precondition(restartFailures.isEmpty, "Immediate restart failed: " + restartFailures.joined(separator: ", "))
        await service.unload()
        print("Live transcription checks passed: bounded snapshots, silence suppression, complete final audio, serialized inference, cancelled late results, and immediate restart after cancelled loading/final recognition.")
    }
}
'''
Path(".build/verification/checks/LiveTranscriptionCheck.swift").write_text(source)
PY
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path .build/cache/CheckModuleCache \
  Tess/Sources/AudioLevelMeter.swift .build/verification/checks/LiveTranscriptionCheck.swift -o .build/verification/checks/live-transcription-check
.build/verification/checks/live-transcription-check
