import AVFoundation
import CoreAudio
import Observation

struct RecordedAudio: Sendable {
    let sessionID: UUID
    let samples: [Float]
    let sampleRate: Int
    let hasSpeech: Bool
    var duration: TimeInterval { Double(samples.count) / Double(sampleRate) }
    func withSessionID(_ id: UUID) -> RecordedAudio {
        RecordedAudio(sessionID: id, samples: samples, sampleRate: sampleRate, hasSpeech: hasSpeech)
    }
}

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

enum RecordingError: LocalizedError {
    case permissionDenied, inputUnavailable, inputChanged, conversionFailed, inputStopped
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "请在系统设置 → 隐私与安全性 → 麦克风中允许 Tess 录音。"
        case .inputUnavailable: return "当前麦克风不可用，请选择其他输入设备。"
        case .inputChanged: return "麦克风已断开或输入发生变化，已保留录下的声音。"
        case .conversionFailed: return "无法读取麦克风声音，请重试或切换麦克风。"
        case .inputStopped: return "麦克风停止提供声音，已保留录下的内容，请重试或切换麦克风。"
        }
    }
}

@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var levelHistory = [Float](repeating: 0, count: 32)
    private(set) var isQuiet = false
    var selectedDeviceID: AudioDeviceID?
    private(set) var devices: [AudioInputDevice] = []
    var onLimit: (() -> Void)?
    var onWarning: (() -> Void)?
    var onError: ((Error) -> Void)?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var buffer: CaptureBuffer?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var finishedAudio: RecordedAudio?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var warned = false
    @ObservationIgnored private var startingID: UUID?
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var meter = AudioLevelMeter()
    @ObservationIgnored private var lastMeterTime: TimeInterval = 0

    func refreshDevices() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return }
        devices = ids.compactMap { id in
            var channelsAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                             mScope: kAudioDevicePropertyScopeInput,
                                                             mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &channelsAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                         mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
            var name: CFString = "麦克风" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr else { return nil }
            return AudioInputDevice(id: id, name: name as String)
        }
    }

    func start(sessionID: UUID) async throws {
        guard !isRecording, startingID == nil else { return }
        startingID = sessionID
        defer { if startingID == sessionID { startingID = nil } }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: allowed = false
        }
        guard startingID == sessionID, !Task.isCancelled else { throw CancellationError() }
        guard allowed else { throw RecordingError.permissionDenied }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if var deviceID = selectedDeviceID {
            guard let audioUnit = input.audioUnit,
                  AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                                       kAudioUnitScope_Global, 0, &deviceID,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else { throw RecordingError.inputUnavailable }
        }
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { throw RecordingError.inputUnavailable }
        let capture = CaptureBuffer(converter: converter, targetFormat: targetFormat)
        // The audio callback runs off the main actor; CaptureBuffer protects its own state.
        input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { @Sendable audio, _ in capture.append(audio) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        buffer = capture
        self.sessionID = sessionID
        finishedAudio = nil
        elapsed = 0
        level = 0
        meter = AudioLevelMeter()
        levelHistory = meter.history
        isQuiet = false
        warned = false
        startedAt = ProcessInfo.processInfo.systemUptime
        lastMeterTime = startedAt
        isRecording = true
        changeObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording, self.sessionID == sessionID else { return }
                _ = self.stop()
                self.onError?(RecordingError.inputChanged)
            }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMeter(sessionID: sessionID) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() -> RecordedAudio? {
        startingID = nil
        guard isRecording, let sessionID, let buffer else { return finishedAudio }
        timer?.invalidate()
        timer = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let capture = buffer.finish()
        let audio = RecordedAudio(sessionID: sessionID, samples: capture.samples, sampleRate: 16_000, hasSpeech: capture.hasSpeech)
        finishedAudio = audio
        self.buffer = nil
        self.sessionID = nil
        isRecording = false
        elapsed = audio.duration
        level = 0
        levelHistory = Array(repeating: 0, count: 32)
        isQuiet = false
        return audio
    }

    func snapshot(sessionID: UUID, maximumDuration: TimeInterval = 12) -> RecordedAudio? {
        guard isRecording, self.sessionID == sessionID,
              let capture = buffer?.snapshot(maximumSamples: Int(maximumDuration * 16_000)) else { return nil }
        return RecordedAudio(sessionID: sessionID, samples: capture, sampleRate: 16_000, hasSpeech: true)
    }

    func cancel(sessionID: UUID) {
        guard startingID == sessionID || self.sessionID == sessionID else { return }
        cancel()
    }

    func cancel() {
        startingID = nil
        _ = stop()
        finishedAudio = nil
        elapsed = 0
    }

    private func updateMeter(sessionID: UUID) {
        guard isRecording, self.sessionID == sessionID, let buffer else { return }
        let status = buffer.status()
        let now = ProcessInfo.processInfo.systemUptime
        elapsed = max(status.duration, now - startedAt)
        meter.update(rms: status.rms, interval: max(0, now - lastMeterTime))
        lastMeterTime = now
        level = meter.level
        levelHistory = meter.history
        isQuiet = meter.quietDuration >= 1.2
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            _ = stop()
            onError?(RecordingError.permissionDenied)
        } else if status.failed {
            _ = stop()
            onError?(RecordingError.conversionFailed)
        } else if now - status.lastInput >= 2 {
            _ = stop()
            onError?(RecordingError.inputStopped)
        } else if elapsed >= 300 {
            _ = stop()
            onLimit?()
        } else if elapsed >= 270, !warned {
            warned = true
            onWarning?()
        }
    }
}

private final class CaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private var samples: [Float] = []
    private var voicedSamples = 0
    private var rms: Float = 0
    private var meterPeak: Float = 0
    private var failed = false
    private var accepting = true
    private var lastInput = ProcessInfo.processInfo.systemUptime
    private var lastVoicedSample = 0
    private var lastSnapshotVoicedSample = 0

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        self.converter = converter
        self.targetFormat = targetFormat
        samples.reserveCapacity(16_000 * 60)
    }

    func append(_ input: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard accepting, samples.count < 16_000 * 300 else { return }
        lastInput = ProcessInfo.processInfo.systemUptime
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 128)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { failed = true; return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { failed = true; return }
        let count = Int(output.frameLength)
        guard count > 0 else { return }
        let values = UnsafeBufferPointer(start: channel, count: count)
        rms = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 } / Float(count))
        meterPeak = max(meterPeak, rms)
        // A conservative energy gate rejects silence before invoking a generative ASR.
        // Noise and speech discrimination still needs real microphone acceptance.
        if rms >= 0.006 {
            voicedSamples += count
            lastVoicedSample = samples.count + count
        }
        samples.append(contentsOf: values)
    }

    func snapshot(maximumSamples: Int) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard accepting, samples.count >= 8_000, maximumSamples > 0,
              lastVoicedSample > lastSnapshotVoicedSample else { return nil }
        let start = max(0, samples.count - maximumSamples)
        let recent = samples[start...]
        let voiced = stride(from: recent.startIndex, to: recent.endIndex, by: 800).reduce(0) { total, start in
            let window = recent[start..<min(start + 800, recent.endIndex)]
            let energy = window.reduce(Float(0)) { $0 + $1 * $1 } / Float(window.count)
            return total + (energy >= 0.006 * 0.006 ? window.count : 0)
        }
        guard voiced >= 4_000 else { return nil }
        lastSnapshotVoicedSample = lastVoicedSample
        return Array(recent)
    }

    func status() -> (duration: Double, rms: Float, failed: Bool, lastInput: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let peak = meterPeak
        meterPeak = 0
        return (Double(samples.count) / 16_000, peak, failed, lastInput)
    }

    func finish() -> (samples: [Float], hasSpeech: Bool) {
        lock.lock()
        defer { lock.unlock() }
        accepting = false
        // Drain the resampler's remaining frames after the final input buffer.
        if let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1024) {
            while true {
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, inputStatus in
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                guard error == nil, let channel = output.floatChannelData?[0] else { break }
                if output.frameLength > 0 {
                    samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
                }
                if status != .haveData || output.frameLength == 0 { break }
            }
        }
        return (samples, voicedSamples >= 16_000 / 4)
    }
}
