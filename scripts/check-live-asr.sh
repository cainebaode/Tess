#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p .build/checks
# Explicit offline model/corpus arguments; never opens a microphone or user settings.
# Usage: zsh scripts/check-live-asr.sh /absolute/Models /absolute/quality /absolute/report.json
python3 - "$@" <<'PY'
from pathlib import Path
import subprocess
import sys

if len(sys.argv) != 4 or not all(Path(value).is_absolute() for value in sys.argv[1:]):
    raise SystemExit("Provide absolute model root, synthetic corpus folder, and report path.")
root = Path.cwd()
products = root / ".build/DerivedData/Build/Products/Release"
source = root / ".build/checks/LiveASRCheck.swift"
source.write_text(r'''
import AVFoundation
import Foundation

@main struct LiveASRCheck {
    struct Measurement: Codable {
        let sample: String
        let stage: String
        let audioSeconds: Double
        let elapsedSeconds: Double
        let transcript: String
    }
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        let service = ASRService(modelsDirectory: URL(fileURLWithPath: args[1]))
        try await service.prepare(model: .qwenSmall)
        var measurements: [Measurement] = []
        func read(_ name: String) throws -> [Float] {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]).appendingPathComponent(name + ".wav"),
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            precondition(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        for name in ["zh_daily", "en_daily", "mixed_terms"] {
            let samples = try read(name)
            let id = UUID()
            service.setRecording(true)
            for seconds in [1, 2, 4, 8, 12] {
                let end = min(samples.count, seconds * 16_000)
                let audio = RecordedAudio(sessionID: id, samples: Array(samples[max(0, end - 12 * 16_000)..<end]),
                                          sampleRate: 16_000, hasSpeech: true)
                let start = ProcessInfo.processInfo.systemUptime
                let text = try await service.transcribePartial(audio, sessionID: id, model: .qwenSmall)
                measurements.append(.init(sample: name, stage: "partial", audioSeconds: audio.duration,
                                           elapsedSeconds: ProcessInfo.processInfo.systemUptime - start, transcript: text))
                print("\(name) partial \(seconds)s: \(text)")
            }
            let audio = RecordedAudio(sessionID: id, samples: samples, sampleRate: 16_000, hasSpeech: true)
            let pending = Task { try await service.transcribePartial(audio, sessionID: id, model: .qwenSmall) }
            try await Task.sleep(for: .milliseconds(10))
            service.setRecording(false)
            let start = ProcessInfo.processInfo.systemUptime
            let text = try await service.transcribe(audio, sessionID: id, model: .qwenSmall)
            measurements.append(.init(sample: name, stage: "final-after-cancel", audioSeconds: audio.duration,
                                       elapsedSeconds: ProcessInfo.processInfo.systemUptime - start, transcript: text))
            if case .success = await pending.result { fatalError("Cancelled preview returned a late success") }
            while service.isTranscribing { await Task.yield() }
        }
        // A five-minute input with a known spoken tail exercises final full-audio delivery.
        let long = try read("long_zh")
        let tail = try read("en_daily")
        var full: [Float] = []
        while full.count < 300 * 16_000 - tail.count { full.append(contentsOf: long) }
        full = Array(full.prefix(300 * 16_000 - tail.count)) + tail
        let id = UUID()
        let start = ProcessInfo.processInfo.systemUptime
        let text = try await service.transcribe(.init(sessionID: id, samples: full, sampleRate: 16_000, hasSpeech: true),
                                                sessionID: id, model: .qwenSmall)
        precondition(text.lowercased().contains("correct document"), "Final speech tail was lost")
        measurements.append(.init(sample: "five-minute-synthetic", stage: "final", audioSeconds: 300,
                                   elapsedSeconds: ProcessInfo.processInfo.systemUptime - start, transcript: text))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(measurements).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
        while service.isTranscribing { await Task.yield() }
        await service.unload()
        print("Offline live-ASR checks passed. Synthetic corpus only; no microphone, human speech, or target-app acceptance.")
    }
}
''')
binary = root / ".build/checks/live-asr-check"
cmd = ["xcrun", "swiftc", "-O", "-swift-version", "6", "-strict-concurrency=complete", "-parse-as-library",
       "-target", "arm64-apple-macos26.0", "-module-cache-path", str(root / ".build/checks/ModuleCache"),
       "-I", str(products)]
for modulemap in [root / ".build/SourcePackages/checkouts/swift-numerics/Sources/_NumericsShims/include/module.modulemap",
                  root / ".build/SourcePackages/checkouts/mlx-swift/Source/Cmlx/include/module.modulemap",
                  root / ".build/DerivedData/Build/Intermediates.noindex/GeneratedModuleMaps/yyjson.modulemap"]:
    cmd += ["-Xcc", "-fmodule-map-file=" + str(modulemap)]
for headers in ["swift-numerics/Sources/_NumericsShims/include", "mlx-swift/Source/Cmlx/include", "yyjson/src"]:
    cmd += ["-Xcc", "-I" + str(root / ".build/SourcePackages/checkouts" / headers)]
cmd += [str(root / "Tess/Sources" / name) for name in ["ASRService.swift", "AudioRecorder.swift", "AudioLevelMeter.swift"]]
cmd += [str(source)] + [str(path) for path in sorted(products.glob("*.o"))]
cmd += ["-lc++", "-framework", "Metal", "-framework", "Accelerate", "-o", str(binary)]
subprocess.run(cmd, check=True)
metallib = binary.with_name("mlx.metallib")
if not metallib.exists():
    metallib.symlink_to(products / "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
subprocess.run([str(binary), *sys.argv[1:]], check=True)
PY
