#if TESS_INTERNAL_CHECKS
import AVFoundation
import Darwin
import Foundation
import CryptoKit

/// Explicit offline CLI mode. It only reads the named model root and corpus.
@MainActor
enum ASRBenchmark {
  struct Sample: Codable {
    let id: String
    let category: String
    let reference: String
    let audioFile: String
    let language: String?
    let source: String?
    let split: String?
    let group: String?
    let terms: [String]?
  }
  struct Result: Codable {
    let id: String
    let iteration: Int
    let durationSeconds: Double
    let elapsedSeconds: Double
    let transcript: String?
    let error: String?
    let peakResidentBytes: Int64
    let context: String?
    let languageOverride: String?
  }
  struct Report: Codable {
    let evidence: String
    let createdAt: Date
    let model: String
    let repository: String
    let modelReceipt: Receipt
    let quantization: String
    let implementationSHA256: String
    let corpusSHA256: String
    let audioSHA256: [String: String]
    let promptSnapshot: String?
    let condition: String
    let operatingSystem: String
    let hardware: String
    let physicalMemoryBytes: UInt64
    let loadSeconds: Double
    let coldInference: Result
    let samples: [Sample]
    let results: [Result]
    let peakResidentBytes: Int64
  }
  struct Receipt: Codable {
    struct File: Codable {
      let path: String
      let size: Int64
      let digest: String
      let sourceRepository: String
      let sourceRevision: String
    }
    let repository: String
    let revision: String
    let runtime: String
    let files: [File]
  }

  static func runFromEnvironment() async -> Int32 {
    do {
      let environment = ProcessInfo.processInfo.environment
      func path(_ name: String) throws -> URL {
        guard let value = environment[name], value.hasPrefix("/") else {
          throw failure("\(name) must name an explicit absolute path.")
        }
        return URL(fileURLWithPath: value).standardizedFileURL
      }
      let models = try path("TESS_BENCHMARK_MODELS")
      guard let model = ASRModel(rawValue: environment["TESS_BENCHMARK_MODEL"] ?? "qwenSmall") else {
        throw failure("Unknown benchmark model.")
      }
      let service = ASRService(modelsDirectory: models)
      if environment["TESS_BENCHMARK_DOWNLOAD_ONLY"] == "1" {
        if !service.isReady(model) { await service.download(model) }
        guard service.isReady(model) else { throw failure(service.lastError ?? "Model download incomplete.") }
        print("Verified benchmark model: \(model.rawValue)")
        return 0
      }
      let corpus = try path("TESS_BENCHMARK_CORPUS")
      let output = try path("TESS_BENCHMARK_OUTPUT")
      let repetitions = min(5, max(1, Int(environment["TESS_BENCHMARK_REPEATS"] ?? "3") ?? 3))
      let context: String?
      if environment["TESS_BENCHMARK_VOCABULARY"] != nil {
        context = try JSONDecoder().decode(SpeechVocabulary.self, from: Data(contentsOf: path("TESS_BENCHMARK_VOCABULARY"))).asrContext
      } else if environment["TESS_BENCHMARK_MEMORIES"] != nil {
        let memories = try JSONDecoder().decode([SpeechMemory].self, from: Data(contentsOf: path("TESS_BENCHMARK_MEMORIES")))
        context = SpeechPromptSnapshot.make(vocabulary: SpeechVocabulary(), learningEnabled: true, memories: memories,
          applicationID: environment["TESS_BENCHMARK_APPLICATION"], supportsHints: model != .whisper).context
      } else { context = nil }
      let languageOverride = environment["TESS_BENCHMARK_LANGUAGE"]
      guard languageOverride == nil || ["auto", "zh", "en"].contains(languageOverride!) else { throw failure("Invalid language override.") }
      let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: corpus))
      guard let first = samples.first, !samples.isEmpty else { throw failure("Empty corpus.") }
      guard Set(samples.map(\.id)).count == samples.count else { throw failure("Duplicate sample IDs.") }
      var groups: [String: Set<String>] = [:]
      var audioHashes: [String: String] = [:]
      for sample in samples {
        guard !sample.audioFile.contains("/"), !sample.audioFile.hasPrefix("."),
              sample.source?.isEmpty == false, ["development", "heldout", "smoke"].contains(sample.split ?? ""),
              sample.group?.isEmpty == false else { throw failure("Each sample needs explicit source, split and original-sentence group; audio must be beside the manifest.") }
        let digest = sha256(try Data(contentsOf: corpus.deletingLastPathComponent().appendingPathComponent(sample.audioFile)))
        audioHashes[sample.audioFile] = digest
        groups["group:" + sample.group!, default: []].insert(sample.split!)
        groups["audio:" + digest, default: []].insert(sample.split!)
        groups["text:" + sample.reference.filter { !$0.isWhitespace }, default: []].insert(sample.split!)
      }
      guard groups.values.allSatisfy({ $0.count == 1 }) else { throw failure("An audio/sentence group crosses evaluation splits.") }
      guard service.isReady(model) else { throw failure("Named model is not verified; benchmark never downloads models.") }
      let receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: service.directory(for: model).appendingPathComponent(".tess-verified.json")))
      guard let implementation = environment["TESS_BENCHMARK_IMPLEMENTATION_SHA256"], implementation.count == 64 else {
        throw failure("Provide the implementation hash recorded when building the internal benchmark.")
      }
      let start = ProcessInfo.processInfo.systemUptime
      try await service.prepare(model: model)
      let loadSeconds = ProcessInfo.processInfo.systemUptime - start
      let cold = try await measure(first, iteration: 0, root: corpus.deletingLastPathComponent(), service: service, model: model,
                                   context: context, languageOverride: languageOverride)
      var results: [Result] = []
      for sample in samples {
        for iteration in 1...repetitions {
          let result = try await measure(sample, iteration: iteration, root: corpus.deletingLastPathComponent(), service: service, model: model,
                                         context: context, languageOverride: languageOverride)
          results.append(result)
          print("ASR benchmark \(sample.id) \(iteration)/\(repetitions): \(String(format: "%.3f", result.elapsedSeconds))s \(result.error == nil ? "completed" : "error")")
        }
      }
      let sources = Set(samples.compactMap(\.source)).sorted().joined(separator: "; ")
      let report = Report(evidence: "Declared sources: \(sources). No text service calls. Technical comparison is not human acceptance.",
                          createdAt: Date(), model: model.rawValue, repository: model.repository,
                          modelReceipt: receipt, quantization: model.detail, implementationSHA256: implementation,
                          corpusSHA256: sha256(try Data(contentsOf: corpus)), audioSHA256: audioHashes,
                          promptSnapshot: context, condition: environment["TESS_BENCHMARK_CONDITION"] ?? "unspecified",
                          operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                          hardware: hardwareModel(), physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                          loadSeconds: loadSeconds, coldInference: cold, samples: samples, results: results,
                          peakResidentBytes: peakResidentBytes())
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(report).write(to: output, options: .atomic)
      await service.unload()
      print("ASR benchmark report: \(output.path)")
      return 0
    } catch {
      print("ASR benchmark stopped: \(error.localizedDescription)")
      return 1
    }
  }

  private static func measure(_ sample: Sample, iteration: Int, root: URL, service: ASRService, model: ASRModel,
                              context: String?, languageOverride: String?) async throws -> Result {
    guard !sample.audioFile.contains("/"), !sample.audioFile.hasPrefix(".") else {
      throw failure("Audio files must be ordinary files beside the manifest.")
    }
    let file = try AVAudioFile(forReading: root.appendingPathComponent(sample.audioFile), commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = file.processingFormat
    guard format.sampleRate == 16_000, format.channelCount == 1, file.length > 0, file.length <= 16_000 * 300,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
      throw failure("Corpus must contain 16 kHz mono audio, at most five minutes per sample.")
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else { throw failure("Cannot decode sample.") }
    let values = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    let id = UUID()
    let speech = values.reduce(Float(0)) { $0 + $1 * $1 } / Float(values.count) >= 0.002 * 0.002
    let audio = RecordedAudio(sessionID: id, samples: values, sampleRate: 16_000, hasSpeech: speech)
    let start = ProcessInfo.processInfo.systemUptime
    var text: String?
    var message: String?
    let language = languageOverride == "auto" ? nil : languageOverride ?? sample.language
    do { text = try await service.transcribe(audio, sessionID: id, language: language, model: model, context: context) }
    catch { message = error.localizedDescription }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let cleanupDeadline = ProcessInfo.processInfo.systemUptime + 5
    while service.isTranscribing, ProcessInfo.processInfo.systemUptime < cleanupDeadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    guard !service.isTranscribing else { throw failure("ASR did not settle after cancellation; benchmark stopped.") }
    return Result(id: sample.id, iteration: iteration, durationSeconds: audio.duration,
                  elapsedSeconds: elapsed, transcript: text, error: message, peakResidentBytes: peakResidentBytes(),
                  context: context, languageOverride: languageOverride)
  }

  private static func peakResidentBytes() -> Int64 {
    var usage = rusage()
    return getrusage(RUSAGE_SELF, &usage) == 0 ? Int64(usage.ru_maxrss) : 0
  }

  private static func hardwareModel() -> String {
    var count = 0
    guard sysctlbyname("hw.model", nil, &count, nil, 0) == 0 else { return "unknown" }
    var data = [CChar](repeating: 0, count: count)
    guard sysctlbyname("hw.model", &data, &count, nil, 0) == 0 else { return "unknown" }
    return String(cString: data)
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "TessASRBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

#endif
