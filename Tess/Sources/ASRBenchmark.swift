#if TESS_INTERNAL_CHECKS
import AVFoundation
import Darwin
import Foundation

/// Explicit offline CLI mode. It only reads the named model root and corpus.
@MainActor
enum ASRBenchmark {
  struct Sample: Codable {
    let id: String
    let category: String
    let reference: String
    let audioFile: String
    let language: String?
  }
  struct Result: Codable {
    let id: String
    let iteration: Int
    let durationSeconds: Double
    let elapsedSeconds: Double
    let transcript: String?
    let error: String?
    let peakResidentBytes: Int64
  }
  struct Report: Codable {
    let evidence = "Synthetic macOS TTS corpus; not microphone or human acceptance. No text service calls."
    let createdAt: Date
    let model: String
    let repository: String
    let operatingSystem: String
    let hardware: String
    let physicalMemoryBytes: UInt64
    let loadSeconds: Double
    let coldInference: Result
    let samples: [Sample]
    let results: [Result]
    let peakResidentBytes: Int64
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
      let corpus = try path("TESS_BENCHMARK_CORPUS")
      let output = try path("TESS_BENCHMARK_OUTPUT")
      guard let model = ASRModel(rawValue: environment["TESS_BENCHMARK_MODEL"] ?? "qwenSmall") else {
        throw failure("Unknown benchmark model.")
      }
      let repetitions = min(5, max(1, Int(environment["TESS_BENCHMARK_REPEATS"] ?? "3") ?? 3))
      let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: corpus))
      guard let first = samples.first, !samples.isEmpty else { throw failure("Empty corpus.") }
      let service = ASRService(modelsDirectory: models)
      guard service.isReady(model) else { throw failure("Named model is not verified; benchmark never downloads models.") }
      let start = ProcessInfo.processInfo.systemUptime
      try await service.prepare(model: model)
      let loadSeconds = ProcessInfo.processInfo.systemUptime - start
      let cold = try await measure(first, iteration: 0, root: corpus.deletingLastPathComponent(), service: service, model: model)
      var results: [Result] = []
      for sample in samples {
        for iteration in 1...repetitions {
          let result = try await measure(sample, iteration: iteration, root: corpus.deletingLastPathComponent(), service: service, model: model)
          results.append(result)
          print("ASR benchmark \(sample.id) \(iteration)/\(repetitions): \(String(format: "%.3f", result.elapsedSeconds))s \(result.error == nil ? "completed" : "error")")
        }
      }
      let report = Report(createdAt: Date(), model: model.rawValue, repository: model.repository,
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

  private static func measure(_ sample: Sample, iteration: Int, root: URL, service: ASRService, model: ASRModel) async throws -> Result {
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
    do { text = try await service.transcribe(audio, sessionID: id, language: sample.language, model: model) }
    catch { message = error.localizedDescription }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let cleanupDeadline = ProcessInfo.processInfo.systemUptime + 5
    while service.isTranscribing, ProcessInfo.processInfo.systemUptime < cleanupDeadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    guard !service.isTranscribing else { throw failure("ASR did not settle after cancellation; benchmark stopped.") }
    return Result(id: sample.id, iteration: iteration, durationSeconds: audio.duration,
                  elapsedSeconds: elapsed, transcript: text, error: message, peakResidentBytes: peakResidentBytes())
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
}

#endif
