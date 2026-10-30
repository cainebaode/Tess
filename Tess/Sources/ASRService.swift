import CryptoKit
import Foundation
import Observation
@preconcurrency import Qwen3ASR
import WhisperASR

enum ASRModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case qwenSmall, qwenLarge, whisper
    var id: String { rawValue }
    var title: String {
        switch self {
        case .qwenSmall: return "Qwen3-ASR 0.6B"
        case .qwenLarge: return "Qwen3-ASR 1.7B"
        case .whisper: return "Whisper large-v3-turbo"
        }
    }
    var detail: String { self == .whisper ? "CoreML FP16 · 本机识别" : "MLX 4-bit · 本机识别" }
    var repository: String {
        switch self {
        case .qwenSmall: return "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
        case .qwenLarge: return "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"
        case .whisper: return "aufklarer/Whisper-Large-v3-Turbo-CoreML"
        }
    }
    var estimatedBytes: Int64 {
        switch self {
        case .qwenSmall: return 713_000_000
        case .qwenLarge: return 2_100_000_000
        case .whisper: return 1_600_000_000
        }
    }
    var requiredFreeBytes: Int64 { Self.requiredFreeBytes(for: estimatedBytes) }
    static func requiredFreeBytes(for bytes: Int64) -> Int64 { bytes * 2 + 512_000_000 }
    fileprivate var patterns: [String] {
        if self == .whisper {
            return ["MelSpectrogram.mlmodelc/", "AudioEncoder.mlmodelc/", "TextDecoder.mlmodelc/",
                    "TextDecoderContextPrefill.mlmodelc/", "generation_config.json", "tokenizer.json", "tokenizer_config.json"]
        }
        return [".safetensors", "config.json", "vocab.json", "merges.txt", "tokenizer_config.json", "model.safetensors.index.json"]
    }
}

enum ASRModelState: Equatable, Sendable {
    case notDownloaded, connecting, fetchingManifest, downloading, verifying, ready, loading, inUse, failed(String)
    var label: String {
        switch self {
        case .notDownloaded: return "未下载"
        case .connecting: return "连接模型源"
        case .fetchingManifest: return "获取文件清单"
        case .downloading: return "下载中"
        case .verifying: return "校验中"
        case .ready: return "可用"
        case .loading: return "加载中"
        case .inUse: return "使用中"
        case .failed(let message): return "失败：\(message)"
        }
    }
}

struct ModelDownloadProgress: Sendable {
    let state: ASRModelState
    var received: Int64 = 0
    var total: Int64?
    var fileName: String?
    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }
}

enum ASRError: LocalizedError {
    case modelNotReady, busy, silence, timedOut, invalidModel(String), insufficientSpace(Int64), http(Int)
    var errorDescription: String? {
        switch self {
        case .modelNotReady: return "请先在设置中下载并校验语音模型。"
        case .busy: return "当前识别尚未结束，请稍后重试。"
        case .silence: return "没有检测到有效声音，请靠近麦克风重试。"
        case .timedOut: return "识别超过 30 秒，已停止等待。录音保留，可主动重试。"
        case .invalidModel(let reason): return "模型校验失败：\(reason)"
        case .insufficientSpace(let bytes): return "可用空间不足，下载需要约 \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))。"
        case .http(let status): return "模型来源返回 HTTP \(status)，请检查网络后重试。"
        }
    }
}

@MainActor
@Observable
final class ASRService {
    var selectedModel: ASRModel = .qwenSmall
    private(set) var states: [ASRModel: ASRModelState] = [:]
    private(set) var downloadProgress: [ASRModel: ModelDownloadProgress] = [:]
    private(set) var isTranscribing = false
    private(set) var lastError: String?
    let modelsDirectory: URL
    @ObservationIgnored private let runtime = ASRRuntime()
    @ObservationIgnored private var downloads: [ASRModel: Task<ModelReceipt, Error>] = [:]
    @ObservationIgnored private var downloadIDs: [ASRModel: UUID] = [:]
    @ObservationIgnored private var activeTask: Task<String, Error>?
    @ObservationIgnored private var activeWait: TranscriptionWait?
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var partialTask: Task<String, Error>?
    @ObservationIgnored private var partialID: UUID?
    @ObservationIgnored private var finalizingID: UUID?
    @ObservationIgnored private var cancellationPending = false
    @ObservationIgnored private var loadingModel: ASRModel?
    @ObservationIgnored private var loadedModel: ASRModel?
    @ObservationIgnored private var recordingProtected = false
    @ObservationIgnored private var pendingUnload: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    init(modelsDirectory: URL? = nil) {
        self.modelsDirectory = modelsDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tess/Models", isDirectory: true)
        for model in ASRModel.allCases {
            states[model] = ModelReceipt.isValid(in: directory(for: model), model: model, checkingModificationDates: !usesBundledModel(model)) ? .ready : .notDownloaded
        }
    }

    private func downloadedDirectory(for model: ASRModel) -> URL { modelsDirectory.appendingPathComponent(model.rawValue, isDirectory: true) }
    private func bundledDirectory(for model: ASRModel) -> URL? {
        guard model == .qwenSmall, let resources = Bundle.main.resourceURL else { return nil }
        let folder = resources.appendingPathComponent("BaseSpeechModel.tessmodel", isDirectory: true)
        // The signed resource bundle seals these files. Disk-image copies may round timestamps.
        return ModelReceipt.isValid(in: folder, model: model, checkingModificationDates: false) ? folder : nil
    }
    func usesBundledModel(_ model: ASRModel) -> Bool {
        !ModelReceipt.isValid(in: downloadedDirectory(for: model), model: model) && bundledDirectory(for: model) != nil
    }
    func directory(for model: ASRModel) -> URL {
        let downloaded = downloadedDirectory(for: model)
        if !ModelReceipt.isValid(in: downloaded, model: model), let bundled = bundledDirectory(for: model) { return bundled }
        return downloaded
    }
    func isReady(_ model: ASRModel) -> Bool {
        switch states[model] {
        case .ready, .loading, .inUse: return true
        // A transient load failure does not invalidate an already verified download.
        case .failed: return ModelReceipt.isValid(in: directory(for: model), model: model, checkingModificationDates: !usesBundledModel(model))
        default: return false
        }
    }
    func diskUsage(_ model: ASRModel) -> Int64 {
        let url = directory(for: model)
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var bytes: Int64 = 0
        for case let file as URL in files {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return bytes
    }

    func download(_ model: ASRModel) async {
        guard downloads[model] == nil, !(recordingProtected && loadedModel == model), loadingModel != model,
              !isTranscribing, partialTask == nil, finalizingID == nil else { return }
        lastError = nil
        states[model] = .connecting
        downloadProgress[model] = nil
        let id = UUID()
        downloadIDs[model] = id
        let folder = downloadedDirectory(for: model)
        if loadedModel == model { invalidateLoadedModel() }
        let unload = pendingUnload
        let service = self
        let task = Task.detached(priority: .utility) {
            await unload?.value
            try Task.checkCancellation()
            return try await PublicModelDownload.download(model, to: folder) { progress in
                Task { @MainActor in
                    guard service.downloadIDs[model] == id else { return }
                    service.downloadProgress[model] = progress
                    service.states[model] = progress.state
                }
            }
        }
        downloads[model] = task
        do {
            let receipt = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard downloadIDs[model] == id, !task.isCancelled else { throw CancellationError() }
            try receipt.save(to: folder)
            guard ModelReceipt.isValid(in: folder, model: model) else { throw ASRError.invalidModel("模型文件不完整或包含其他版本权重") }
            states[model] = .ready
            let total = receipt.files.reduce(Int64(0)) { $0 + $1.size }
            downloadProgress[model] = .init(state: .ready, received: total, total: total)
        } catch {
            guard downloadIDs[model] == id else { return }
            if error is CancellationError || task.isCancelled {
                states[model] = .notDownloaded
            } else {
                let message: String
                if let networkError = error as? URLError {
                    message = networkError.code == .timedOut
                        ? "模型源连接或传输超时，请检查网络后重试。已完成的文件会保留。"
                        : "无法从 Hugging Face 下载模型：\(networkError.localizedDescription) 请检查网络后重试。"
                } else { message = error.localizedDescription }
                lastError = message
                states[model] = .failed(message)
            }
        }
        if downloadIDs[model] == id {
            downloads[model] = nil
            downloadIDs[model] = nil
        }
    }

    func cancelDownload(_ model: ASRModel) { downloads[model]?.cancel() }

    func delete(_ model: ASRModel) throws {
        guard downloads[model] == nil, !(recordingProtected && loadedModel == model), loadingModel != model,
              !isTranscribing, partialTask == nil, finalizingID == nil else { throw ASRError.busy }
        let folder = downloadedDirectory(for: model)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        if loadedModel == model { invalidateLoadedModel() }
        states[model] = bundledDirectory(for: model) == nil ? .notDownloaded : .ready
        downloadProgress[model] = nil
    }

    func prepare(model: ASRModel? = nil) async throws {
        let model = model ?? selectedModel
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        // A quick restart waits for cancelled GPU/loading work to release the runtime.
        // Ordinary concurrent requests still fail as busy instead of being queued.
        while (cancellationPending || activeTask?.isCancelled == true),
              loadingModel != nil || isTranscribing || partialTask != nil {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ASRError.busy }
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        cancellationPending = false
        guard !isTranscribing, loadingModel == nil else { throw ASRError.busy }
        guard isReady(model), ModelReceipt.isValid(in: directory(for: model), model: model, checkingModificationDates: !usesBundledModel(model)) else {
            states[model] = .notDownloaded
            throw ASRError.modelNotReady
        }
        idleTask?.cancel()
        loadingModel = model
        states[model] = .loading
        do {
            await drainPartialTranscription()
            try Task.checkCancellation()
            await pendingUnload?.value
            pendingUnload = nil
            loadedModel = nil
            try await runtime.prepare(model: model, directory: directory(for: model))
            try Task.checkCancellation()
            loadedModel = model
            states[model] = .ready
            loadingModel = nil
            scheduleUnload()
        } catch {
            loadingModel = nil
            let message = ModelReceipt.isValid(in: directory(for: model), model: model, checkingModificationDates: !usesBundledModel(model))
                ? "\(error.localizedDescription) 重新开始录音可重试加载，无需重新下载。"
                : error.localizedDescription
            states[model] = error is CancellationError ? .ready : .failed(message)
            lastError = error is CancellationError ? nil : message
            throw error
        }
    }

    func transcribePartial(_ audio: RecordedAudio, sessionID: UUID, language: String? = nil, model: ASRModel? = nil, context: String? = nil) async throws -> String {
        try Task.checkCancellation()
        guard audio.sessionID == sessionID, recordingProtected else { throw CancellationError() }
        guard !isTranscribing, finalizingID == nil, loadingModel == nil, partialTask == nil else { throw ASRError.busy }
        guard audio.hasSpeech, !audio.samples.isEmpty else { throw ASRError.silence }
        let model = model ?? loadedModel ?? selectedModel
        guard loadedModel == model else { throw ASRError.modelNotReady }
        idleTask?.cancel()
        let id = UUID()
        let job = Task.detached(priority: .userInitiated) { [runtime] in
            try await runtime.transcribe(audio.samples, model: model, language: language, context: context)
        }
        partialID = id
        partialTask = job
        defer {
            if partialID == id {
                partialID = nil
                partialTask = nil
                scheduleUnload()
            }
        }
        let text = try await withTaskCancellationHandler {
            try await job.value
        } onCancel: { job.cancel() }
        try Task.checkCancellation()
        guard !job.isCancelled else { throw CancellationError() }
        return text
    }

    func cancelPartialTranscription() { partialTask?.cancel() }

    private func drainPartialTranscription() async {
        guard let job = partialTask else { return }
        let id = partialID
        job.cancel()
        _ = await job.result
        if partialID == id {
            partialID = nil
            partialTask = nil
        }
    }

    func transcribe(_ audio: RecordedAudio, sessionID: UUID, language: String? = nil, model: ASRModel? = nil, context: String? = nil) async throws -> String {
        guard !isTranscribing, finalizingID == nil else { throw ASRError.busy }
        guard audio.sessionID == sessionID else { throw CancellationError() }
        guard audio.hasSpeech, !audio.samples.isEmpty else { throw ASRError.silence }
        let finalizing = UUID()
        finalizingID = finalizing
        defer { if finalizingID == finalizing { finalizingID = nil } }
        // Let the cancelled preview release the model before the final result's timeout starts.
        await drainPartialTranscription()
        try Task.checkCancellation()
        let model = model ?? (recordingProtected ? (loadedModel ?? selectedModel) : selectedModel)
        if loadedModel != model { try await prepare(model: model) }
        idleTask?.cancel()
        isTranscribing = true
        states[model] = .inUse
        activeID = sessionID
        let job = Task.detached(priority: .userInitiated) { [runtime] in
            try await runtime.transcribe(audio.samples, model: model, language: language, context: context)
        }
        activeTask = job
        let wait = TranscriptionWait()
        activeWait = wait
        let timeout = Task.detached {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            job.cancel()
            wait.finish(.failure(ASRError.timedOut))
        }
        Task { [weak self] in
            let result = await job.result
            timeout.cancel()
            wait.finish(result)
            guard let self, self.activeID == sessionID else { return }
            self.activeID = nil
            self.activeTask = nil
            self.activeWait = nil
            self.isTranscribing = false
            self.states[model] = .ready
            self.scheduleUnload()
        }
        do {
            let text = try await withTaskCancellationHandler {
                try await wait.value()
            } onCancel: {
                job.cancel()
                wait.finish(.failure(CancellationError()))
            }
            try Task.checkCancellation()
            return text
        } catch {
            if !(error is CancellationError) { lastError = error.localizedDescription }
            throw error
        }
    }

    func cancel() {
        cancellationPending = true
        cancelPartialTranscription()
        activeTask?.cancel()
        activeWait?.finish(.failure(CancellationError()))
    }

    func setRecording(_ value: Bool) {
        recordingProtected = value
        idleTask?.cancel()
        if !value {
            cancelPartialTranscription()
            scheduleUnload()
        }
    }

    func unload() async {
        guard !isTranscribing, !recordingProtected, loadingModel == nil, partialTask == nil, finalizingID == nil else { return }
        idleTask?.cancel()
        await pendingUnload?.value
        pendingUnload = nil
        await runtime.unload()
        loadedModel = nil
    }

    private func invalidateLoadedModel() {
        idleTask?.cancel()
        let previous = pendingUnload
        let runtime = runtime
        pendingUnload = Task {
            await previous?.value
            await runtime.unload()
        }
        loadedModel = nil
    }

    private func scheduleUnload() {
        idleTask?.cancel()
        guard !recordingProtected, !isTranscribing, partialTask == nil else { return }
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            await self?.unload()
        }
    }
}

private actor ASRRuntime {
    private var qwen: Qwen3ASRModel?
    private var whisper: WhisperASRModel?
    private var loaded: ASRModel?
    func prepare(model: ASRModel, directory: URL) async throws {
        if loaded == model { return }
        unload()
        try Task.checkCancellation()
        do {
            if model == .whisper {
                whisper = try await WhisperASRModel.fromPretrained(cacheDir: directory, offlineMode: true)
            } else {
                qwen = try await Qwen3ASRModel.fromPretrained(modelId: model.repository, cacheDir: directory, offlineMode: true)
            }
            try Task.checkCancellation()
            loaded = model
        } catch {
            unload()
            throw error
        }
    }
    func unload() {
        qwen?.unload()
        qwen = nil
        whisper = nil
        loaded = nil
    }
    func transcribe(_ samples: [Float], model: ASRModel, language: String?, context: String?) async throws -> String {
        guard loaded == model else { throw ASRError.modelNotReady }
        var offset = 0
        var output: [String] = []
        while offset < samples.count {
            try Task.checkCancellation()
            let maximum = min(offset + (model == .whisper ? 10 : 20) * 16_000, samples.count)
            let end = chunkEnd(in: samples, start: offset, maximum: maximum)
            let chunk = Array(samples[offset..<end])
            // Gate short windows so a spoken tail after silence is not discarded.
            let hasSound = stride(from: 0, to: chunk.count, by: 800).contains { start in
                let window = chunk[start..<min(start + 800, chunk.count)]
                return window.reduce(Float(0)) { $0 + $1 * $1 } / Float(window.count) >= 0.002 * 0.002
            }
            if hasSound {
                let text: String
                if let qwen {
                    let hint = language == "zh" ? "Chinese" : language == "en" ? "English" : language
                    text = try qwen.transcribeCheckingCancellation(audio: chunk, sampleRate: 16_000,
                        options: Qwen3DecodingOptions(maxTokens: 768, language: hint, context: context))
                } else if let whisper {
                    text = try await whisper.transcribeAudio(chunk, sampleRate: 16_000, language: language)
                } else { throw ASRError.modelNotReady }
                try Task.checkCancellation()
                let clean = text.replacingOccurrences(of: "<\\|[^>]*\\|>|<asr_text>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { output.append(clean) }
            }
            offset = end
        }
        let text = output.joined(separator: " ")
        guard !text.isEmpty else { throw ASRError.silence }
        return text
    }
    private func chunkEnd(in samples: [Float], start: Int, maximum: Int) -> Int {
        guard maximum < samples.count else { return maximum }
        var best = maximum
        var quietest = Float.infinity
        for position in stride(from: max(start + 800, maximum - 2 * 16_000), to: maximum - 800, by: 800) {
            let window = samples[position..<(position + 800)]
            let energy = window.reduce(Float(0)) { $0 + $1 * $1 } / Float(window.count)
            if energy < quietest { quietest = energy; best = position + 400 }
        }
        return quietest < 0.006 * 0.006 ? best : maximum
    }
}

private final class TranscriptionWait: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String, Error>?
    private var continuation: CheckedContinuation<String, Error>?
    func value() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result { lock.unlock(); continuation.resume(with: result) }
            else { self.continuation = continuation; lock.unlock() }
        }
    }
    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private struct ModelReceipt: Codable, Sendable {
    struct File: Codable, Sendable {
        let path: String
        let size: Int64
        let digest: String
        let modificationDate: Date
        let sourceRepository: String
        let sourceRevision: String
    }
    let repository: String
    let revision: String
    let runtime: String
    let files: [File]
    static let fileName = ".tess-verified.json"
    func save(to directory: URL) throws {
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
    static func isValid(in directory: URL, model: ASRModel, checkingModificationDates: Bool = true) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let receipt = try? JSONDecoder().decode(Self.self, from: data), receipt.repository == model.repository,
              receipt.runtime == "speech-swift cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa",
              complete(paths: Set(receipt.files.map(\.path)), model: model),
              Set(receipt.files.map(\.path)).count == receipt.files.count else { return false }
        if model != .whisper {
            let actual = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            let weights = Set(actual.filter { $0.pathExtension == "safetensors" }.map(\.lastPathComponent))
            guard weights == Set(receipt.files.filter { $0.path.hasSuffix(".safetensors") }.map(\.path)) else { return false }
            let index = directory.appendingPathComponent("model.safetensors.index.json")
            if receipt.files.contains(where: { $0.path == index.lastPathComponent }) {
                guard let data = try? Data(contentsOf: index),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let map = json["weight_map"] as? [String: String], !map.isEmpty,
                      Set(map.values).isSubset(of: weights) else { return false }
            }
        }
        return receipt.files.allSatisfy { file in
            guard let url = try? PublicModelDownload.safeURL(file.path, in: directory),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  let date = attributes[.modificationDate] as? Date else { return false }
            return size.int64Value == file.size && (!checkingModificationDates || date == file.modificationDate)
        }
    }
    static func complete(paths: Set<String>, model: ASRModel) -> Bool {
        if model == .whisper {
            let bundles = ["MelSpectrogram", "AudioEncoder", "TextDecoder", "TextDecoderContextPrefill"]
            let required = bundles.flatMap { name in
                ["\(name).mlmodelc/metadata.json", "\(name).mlmodelc/model.mil", "\(name).mlmodelc/weights/weight.bin"]
            } + ["generation_config.json", "tokenizer.json", "tokenizer_config.json"]
            return Set(required).isSubset(of: paths)
        }
        return Set(["config.json", "vocab.json", "merges.txt", "tokenizer_config.json"]).isSubset(of: paths)
            && paths.contains(where: { $0.hasSuffix(".safetensors") && !$0.contains("/") })
    }
}

private enum PublicModelDownload {
    struct RemoteFile: Sendable { let path: String; let size: Int64; let digest: String; let lfs: Bool; let repository: String; let revision: String }
    static func download(_ model: ASRModel, to directory: URL,
                         progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws -> ModelReceipt {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let revision = try await Self.revision(for: model.repository, session: session)
        progress(.init(state: .fetchingManifest))
        var remote = try await manifest(model.repository, revision: revision, session: session)
        remote = remote.filter { file in model.patterns.contains { pattern in pattern.hasPrefix(".") ? file.path.hasSuffix(pattern) : pattern.hasSuffix("/") ? file.path.hasPrefix(pattern) : file.path == pattern } }
        if model == .whisper {
            let missing = ["tokenizer.json", "tokenizer_config.json"].filter { required in !remote.contains(where: { $0.path == required }) }
            if !missing.isEmpty {
                let tokenizerRepository = "openai/whisper-large-v3"
                let tokenizerRevision = try await Self.revision(for: tokenizerRepository, session: session)
                let tokenizerFiles = try await manifest(tokenizerRepository, revision: tokenizerRevision, session: session)
                for required in missing {
                    guard let file = tokenizerFiles.first(where: { $0.path == required }) else { throw ASRError.invalidModel("缺少 \(required)") }
                    remote.append(file)
                }
            }
        } else {
            guard remote.contains(where: { $0.path.hasSuffix(".safetensors") }),
                  remote.contains(where: { $0.path == "vocab.json" }),
                  remote.contains(where: { $0.path == "config.json" }) else { throw ASRError.invalidModel("权重或词表缺失") }
        }
        guard ModelReceipt.complete(paths: Set(remote.map(\.path)), model: model),
              Set(remote.map(\.path)).count == remote.count else { throw ASRError.invalidModel("来源缺少必要权重、词表或 CoreML 文件") }
        let total = remote.reduce(Int64(0)) { $0 + $1.size }
        let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        let needed = ASRModel.requiredFreeBytes(for: total)
        guard capacity >= needed else { throw ASRError.insufficientSpace(needed) }
        var completed: Int64 = 0
        var records: [ModelReceipt.File] = []
        for file in remote {
            try Task.checkCancellation()
            progress(.init(state: .verifying, received: completed, total: total, fileName: file.path))
            let destination = try safeURL(file.path, in: directory)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let valid: Bool
            do { valid = try verify(file, at: destination) }
            catch is CancellationError { throw CancellationError() }
            catch { valid = false }
            if !valid {
                guard let base = URL(string: "https://huggingface.co/\(file.repository)/resolve/\(file.revision)") else { throw ASRError.invalidModel("来源地址错误") }
                let url = base.appendingPathComponent(file.path)
                let prior = completed
                let temporary = directory.appendingPathComponent(".tess-download-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: temporary) }
                progress(.init(state: .connecting, received: completed, total: total, fileName: file.path))
                let transfer = ModelFileTransfer(destination: temporary) { received in
                    progress(.init(state: .downloading, received: prior + min(received, file.size), total: total, fileName: file.path))
                }
                let response = try await transfer.download(URLRequest(url: url))
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw ASRError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
                try Task.checkCancellation()
                progress(.init(state: .verifying, received: completed + file.size, total: total, fileName: file.path))
                guard try verify(file, at: temporary) else { throw ASRError.invalidModel(file.path) }
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: temporary, to: destination)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            let attributes = try fm.attributesOfItem(atPath: destination.path)
            records.append(.init(path: file.path, size: file.size, digest: file.digest,
                                 modificationDate: attributes[.modificationDate] as? Date ?? .distantPast,
                                 sourceRepository: file.repository, sourceRevision: file.revision))
            completed += file.size
            progress(.init(state: .downloading, received: completed, total: total, fileName: file.path))
        }
        try Task.checkCancellation()
        if model != .whisper {
            let allowed = Set(records.filter { $0.path.hasSuffix(".safetensors") }.map(\.path))
            let actual = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard Set(actual.filter { $0.pathExtension == "safetensors" }.map(\.lastPathComponent)) == allowed else {
                throw ASRError.invalidModel("目录混有其他版本的权重，请删除该模型后重新下载")
            }
        }
        return ModelReceipt(repository: model.repository, revision: revision,
                            runtime: "speech-swift cbcdfc6be5e723952d29ab6e32af5e22ad8e70fa", files: records)
    }
    static func safeURL(_ path: String, in directory: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\"), !path.contains("\0") else { throw ASRError.invalidModel("不安全的文件路径") }
        let destination = directory.appendingPathComponent(path).standardizedFileURL
        guard destination.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/") else { throw ASRError.invalidModel("模型文件超出缓存目录") }
        return destination
    }
    static func json(_ address: String, session: URLSession) async throws -> Any {
        guard let url = URL(string: address) else { throw ASRError.invalidModel("来源地址错误") }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ASRError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return try JSONSerialization.jsonObject(with: data)
    }
    static func revision(for repository: String, session: URLSession) async throws -> String {
        let info = try await json("https://huggingface.co/api/models/\(repository)", session: session) as? [String: Any]
        guard let revision = info?["sha"] as? String, revision.count == 40, revision.allSatisfy({ $0.isHexDigit }) else { throw ASRError.invalidModel("来源未返回固定版本") }
        return revision
    }
    static func manifest(_ repository: String, revision: String, session: URLSession) async throws -> [RemoteFile] {
        var next: URL? = URL(string: "https://huggingface.co/api/models/\(repository)/tree/\(revision)?recursive=true&expand=true")
        var entries: [[String: Any]] = []
        var pages = 0
        while let url = next {
            guard pages < 32, url.host == "huggingface.co", url.path.hasPrefix("/api/models/\(repository)/tree/") else { throw ASRError.invalidModel("文件清单分页无效") }
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ASRError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            guard let page = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ASRError.invalidModel("文件清单格式错误") }
            entries.append(contentsOf: page)
            pages += 1
            next = nil
            if let link = http.value(forHTTPHeaderField: "Link") {
                for part in link.components(separatedBy: ",") where part.contains("rel=\"next\"") {
                    if let begin = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">") { next = URL(string: String(part[part.index(after: begin)..<end])) }
                }
            }
        }
        return try entries.compactMap { entry in
            guard entry["type"] as? String == "file", let path = entry["path"] as? String,
                  let size = entry["size"] as? NSNumber else { return nil }
            let lfs = entry["lfs"] as? [String: Any]
            guard let digest = (lfs?["oid"] as? String) ?? (entry["oid"] as? String), !digest.isEmpty else { throw ASRError.invalidModel("\(path) 缺少校验值") }
            return RemoteFile(path: path, size: size.int64Value, digest: digest, lfs: lfs != nil, repository: repository, revision: revision)
        }
    }
    static func verify(_ file: RemoteFile, at url: URL) throws -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.int64Value == file.size else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha256 = SHA256()
        var sha1 = Insecure.SHA1()
        if !file.lfs { sha1.update(data: Data("blob \(file.size)\0".utf8)) }
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            if file.lfs { sha256.update(data: data) } else { sha1.update(data: data) }
        }
        let actual = file.lfs ? sha256.finalize().map { String(format: "%02x", $0) }.joined() : sha1.finalize().map { String(format: "%02x", $0) }.joined()
        return actual == file.digest
    }
}

private final class ModelFileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var cancelled = false
    // Only accessed on the session's serial delegate queue.
    private var result: Result<URLResponse, Error>?
    private var lastProgress = Date.distantPast

    init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ request: URLRequest) async throws -> URLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCredentialStorage = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 4 * 60 * 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                // Async/completion-handler downloads do not deliver didWriteData callbacks.
                let task = session.downloadTask(with: request)
                self.task = task
                task.resume()
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            self.task?.cancel()
            self.lock.unlock()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response else { throw URLError(.badServerResponse) }
            // The system removes location after this callback returns.
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            result = .success(response)
        } catch { result = .failure(error) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastProgress) >= 0.1 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastProgress = now
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        self.task = nil
        let completed: Result<URLResponse, Error> = cancelled ? .failure(CancellationError())
            : error.map { .failure($0) } ?? result ?? .failure(URLError(.badServerResponse))
        lock.unlock()
        session.finishTasksAndInvalidate()
        continuation?.resume(with: completed)
    }
}
