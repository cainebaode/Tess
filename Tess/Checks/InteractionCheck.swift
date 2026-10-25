import AppKit
import Foundation

// Only external effects are replaced. The executable compiles production AppModel.swift.
@MainActor final class ASRService {
    var selectedModel: ASRModel = .qwenSmall
    var transcripts: [Result<String, Error>] = [.success("隔离语音结果")]
    var partials = ["第一段转录", "第一段修正后的转录"]
    var holdPartial = false
    private(set) var partialCalls = 0
    private(set) var pendingPartial: CheckedContinuation<String, Never>?
    init(modelsDirectory: URL) {}
    func isReady(_ model: ASRModel) -> Bool { true }
    func prepare(model: ASRModel?) async throws {}
    func setRecording(_ value: Bool) {}
    func cancel() {}
    func cancelPartialTranscription() {}
    func transcribePartial(_ audio: RecordedAudio, sessionID: UUID, language: String?, model: ASRModel?) async throws -> String {
        precondition(audio.sessionID == sessionID)
        partialCalls += 1
        if holdPartial { return await withCheckedContinuation { pendingPartial = $0 } }
        return partials.count > 1 ? partials.removeFirst() : partials[0]
    }
    func completeHeldPartial(_ text: String) {
        let continuation = pendingPartial; pendingPartial = nil; continuation?.resume(returning: text)
    }
    func transcribe(_ audio: RecordedAudio, sessionID: UUID, language: String?, model: ASRModel?) async throws -> String {
        precondition(audio.sessionID == sessionID, "Retry audio must receive its new session ID")
        return try transcripts.removeFirst().get()
    }
}
enum ASRError: Error { case silence, isolatedFailure }

@MainActor final class AudioRecorder {
    var selectedDeviceID: UInt32?
    var elapsed: TimeInterval = 0
    var levelHistory = [Float](repeating: 0, count: 32)
    var isQuiet = false
    var hasSpeech = true
    var onLimit: (() -> Void)?
    var onWarning: (() -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var startCount = 0
    private var sessionID: UUID?
    func start(sessionID: UUID) async throws { self.sessionID = sessionID; startCount += 1 }
    func stop() -> RecordedAudio? {
        sessionID.map { RecordedAudio(sessionID: $0, samples: [0.1], sampleRate: 16_000, hasSpeech: hasSpeech) }
    }
    func cancel() { sessionID = nil; elapsed = 0 }
    func cancel(sessionID: UUID) { if self.sessionID == sessionID { cancel() } }
    func snapshot(sessionID: UUID) -> RecordedAudio? { self.sessionID == sessionID ? stop() : nil }
}

@MainActor final class HotkeyService {
    var lastError: String?
    var onPress: ((ShortcutAction, TimeInterval) -> Void)?
    var onRelease: ((ShortcutAction, TimeInterval) -> Void)?
    var onCancel: (() -> Void)?
    var onRecordInterrupt: ((ShortcutAction) -> Void)?
    private(set) var registerCount = 0
    private(set) var refreshCount = 0
    private(set) var interruptCount = 0
    private(set) var suspended = false
    func register(_ bindings: [ShortcutAction: ShortcutBinding]) { registerCount += 1; suspended = false }
    func set(_ action: ShortcutAction, binding: ShortcutBinding?) -> Bool { true }
    func enableEscape(_ enabled: Bool) {}
    func refreshFn() { refreshCount += 1 }
    func interruptForSessionChange() { interruptCount += 1 }
    func suspend() { suspended = true }
}

@MainActor final class DeliveryService {
    final class Target {
        var applicationName = "Isolated editor"
        var screenID: CGDirectDisplayID? = nil
        private(set) var stopTrackingCount = 0
        func stopTracking() { stopTrackingCount += 1 }
    }
    enum Outcome { case attemptedPaste, copiedToClipboard, unavailable(String) }
    var onCapture: (() -> Void)?
    var holdDelivery = false
    private(set) var capturedTargets: [Target] = []
    private(set) var pendingDelivery: CheckedContinuation<Void, Never>?
    private(set) var completedDeliveries = 0
    private(set) var delivered: [String] = []
    init(diagnosticURL: URL? = nil) {}
    func startDesktopAccessibilityPreparation() {}
    func failureDescription(chinese: Bool) -> String? { nil }
    func captureTarget(compatibilityShortcut: (keyCode: UInt32, modifiers: UInt32)? = nil) -> Target? {
        onCapture?()
        let target = Target()
        capturedTargets.append(target)
        return target
    }
    func deliverVoice(text: String, target: Target?) async -> Outcome {
        precondition(target != nil, "Ordinary voice delivery must retain a target")
        delivered.append(text)
        if holdDelivery { await withCheckedContinuation { pendingDelivery = $0 } }
        completedDeliveries += 1
        return .attemptedPaste
    }
    func completeHeldDelivery() {
        let continuation = pendingDelivery; pendingDelivery = nil; continuation?.resume()
    }
    func paste(text: String, target: Target?) async -> Outcome { .attemptedPaste }
    func copyText(_ text: String) -> Bool { true }
}

@MainActor final class CaptureService {
    enum Failure { case permissionRequired, captureFailed }
    private(set) var lastError: String?
    private(set) var failure: Failure?
    let capturesDirectory: URL
    var nextFailure: Failure?
    var nextURL: URL?
    var holdResponse = false
    private(set) var calls = 0
    private(set) var pending: CheckedContinuation<URL?, Never>?
    private(set) var deleted: [URL] = []
    init(capturesDirectory: URL) { self.capturesDirectory = capturesDirectory }
    func captureSelection() async -> URL? {
        calls += 1
        failure = nextFailure
        lastError = nextFailure == nil ? nil : "Isolated capture failure"
        if holdResponse { return await withCheckedContinuation { pending = $0 } }
        return nextURL
    }
    // Deliberately allow a late OS completion after cancellation.
    func cancel() {}
    func completeHeld(with url: URL?) { let wait = pending; pending = nil; wait?.resume(returning: url) }
    func delete(_ url: URL) {
        precondition(url.deletingLastPathComponent() == capturesDirectory)
        deleted.append(url)
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor private final class Scenario {
    let app: AppModel
    let old: SavedResult
    let oldImage: URL
    var events: [String] = []
    var openedResults: Int { events.filter { $0 == "result" }.count }

    init(root: URL) throws {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let captures = directory.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        oldImage = captures.appendingPathComponent(UUID().uuidString + ".png")
        try Data("isolated image fixture".utf8).write(to: oldImage)
        old = SavedResult(original: "隔离旧内容", output: "隔离旧内容", imageName: oldImage.lastPathComponent, mode: .raw, origin: "screenshot")
        for name in ["recent.json", "draft.json"] { try JSONEncoder().encode(old).write(to: directory.appendingPathComponent(name)) }
        setenv("TESS_DATA_DIRECTORY", directory.path, 1)
        app = AppModel()
        app.preferences.completedOnboarding = true
        app.preferences.language = .chinese
        app.preferences.textMode = .raw
        app.preferences.alwaysPreview = false
        app.delivery.onCapture = { [weak self] in self?.events.append("target") }
        app.hideWindows = { [weak self] in self?.events.append("hideWindows") }
        app.showHUD = { [weak self] in self?.events.append("showHUD") }
        app.hideHUD = { [weak self] in self?.events.append("hideHUD") }
        app.hideHUDImmediately = { [weak self] in self?.events.append("hideHUDImmediately") }
        app.openResult = { [weak self] in self?.events.append("result") }
        app.openSettings = { preconditionFailure("No interaction case should need real settings") }
    }

    func newImage() throws -> URL {
        let url = app.capture.capturesDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try Data("isolated new image".utf8).write(to: url)
        return url
    }

    func assertOldContentIntact() throws {
        precondition(app.result?.id == old.id && app.result?.output == old.output)
        precondition(!app.isImageOnlyResult, "An existing image with text must keep its text result view")
        precondition(FileManager.default.fileExists(atPath: oldImage.path))
        let saved = try JSONDecoder().decode(SavedResult.self, from: Data(contentsOf: app.directory.appendingPathComponent("draft.json")))
        precondition(saved.id == old.id && saved.imageName == old.imageName)
    }
}

@main @MainActor struct InteractionCheck {
    private static func checkPromptPreferences(root: URL) async throws {
        var previous = AppPreferences()
        previous.language = .english
        previous.holdToRecord = false
        previous.alwaysPreview = true
        previous.textMode = .polish
        previous.recognitionLanguage = "en"
        previous.shortcutVersion = 2
        previous.completedOnboarding = true
        previous.onboardingStep = 4
        previous.onboardingPracticePassed = true
        previous.asrModel = .qwenSmall
        previous.microphoneID = 123
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as! [String: Any]
        legacyJSON.removeValue(forKey: "textPrompts")
        let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        precondition(restored.textPrompts == nil, "Older preferences must use the default prompts")
        precondition(restored.language == previous.language && restored.holdToRecord == previous.holdToRecord && restored.alwaysPreview == previous.alwaysPreview)
        precondition(restored.textMode == previous.textMode && restored.recognitionLanguage == previous.recognitionLanguage && restored.bindings == previous.bindings)
        precondition(restored.shortcutVersion == previous.shortcutVersion && restored.completedOnboarding == previous.completedOnboarding)
        precondition(restored.onboardingStep == previous.onboardingStep && restored.onboardingPracticePassed == previous.onboardingPracticePassed)
        precondition(restored.asrModel == previous.asrModel && restored.microphoneID == previous.microphoneID)

        let scenario = try Scenario(root: root)
        var prompts = TextPrompt.defaults
        let custom = TextPrompt(name: "我的英文摘要", instructions: "提炼为三条英文要点。")
        prompts.append(custom)
        precondition(scenario.app.savePromptLibrary(prompts))
        precondition(scenario.app.setPrompt(custom.id, for: .custom1))
        precondition(scenario.app.setPrompt(custom.id, for: .custom2), "Both shortcuts may share a prompt")
        precondition(!scenario.app.savePromptLibrary(prompts.filter { $0.id != custom.id }), "Bound prompts cannot be removed")
        precondition(!scenario.app.savePromptLibrary(prompts + [custom]), "Prompt IDs must be unique")
        precondition(!scenario.app.savePromptLibrary(prompts + [TextPrompt(name: "", instructions: "内容")]))
        precondition(!scenario.app.savePromptLibrary(prompts + [TextPrompt(name: "名称", instructions: " \n")]))
        precondition(!scenario.app.setShortcut(.record, binding: nil), "Fn cannot be removed")
        precondition(!scenario.app.setShortcut(.custom1, binding: .fn), "Fn stays reserved for plain dictation")
        let preferencesFile = scenario.app.directory.appendingPathComponent("preferences.json")
        let persisted = try JSONDecoder().decode(AppPreferences.self, from: Data(contentsOf: preferencesFile))
        precondition(persisted.availablePrompts == prompts && persisted.prompt(for: .custom1) == custom && persisted.prompt(for: .custom2) == custom)
        let reopened = AppModel()
        precondition(reopened.preferences.availablePrompts == prompts && reopened.preferences.prompt(for: .custom2) == custom)
        precondition(reopened.preferences.completedOnboarding && reopened.preferences.language == .chinese)

        scenario.app.preferences.textMode = .custom1
        scenario.app.hotkeys.onPress?(.record, 1)
        try await waitFor("Fn plain dictation") { scenario.app.isRecording }
        precondition(scenario.app.activeMode == .raw && !scenario.app.hudSnapshot.includesEditing,
                     "Fn must ignore the selected processing prompt and work without a text service")
        scenario.app.cancel()

        var configuration = APIPreset.all.first { $0.id == "ollama" }!.configuration()
        configuration.modelID = "isolated-no-network"
        precondition(scenario.app.configurations.save(configuration))
        let saved = scenario.app.configurations.configurations[0]
        precondition(scenario.app.configurations.markTested(saved, result: TextResult(original: "样例", output: "结果", modelID: configuration.modelID)))
        precondition(scenario.app.configurations.setCurrent(saved.id))
        for (index, action) in [ShortcutAction.custom1, .custom2].enumerated() {
            scenario.app.hotkeys.onPress?(action, Double(index + 2))
            try await waitFor("custom shortcut recording") { scenario.app.isRecording }
            precondition(scenario.app.activeMode == action.recordMode && scenario.app.hudSnapshot.mode == custom.name)
            prompts[prompts.count - 1].name = "下次生效的名称"
            precondition(scenario.app.savePromptLibrary(prompts))
            precondition(scenario.app.setPrompt("digest", for: action.recordMode!))
            precondition(scenario.app.hudSnapshot.mode == custom.name, "An active session must retain its prompt snapshot")
            scenario.app.cancel()
            precondition(scenario.app.setPrompt(custom.id, for: action.recordMode!))
            prompts[prompts.count - 1] = custom
            precondition(scenario.app.savePromptLibrary(prompts))
        }
        try FileManager.default.removeItem(at: preferencesFile)
        try FileManager.default.createDirectory(at: preferencesFile, withIntermediateDirectories: true)
        precondition(!scenario.app.savePromptLibrary(TextPrompt.defaults + [custom]), "A failed write must be reported")
        precondition(!scenario.app.setPrompt("rewrite", for: .custom1))
        precondition(scenario.app.preferences.availablePrompts == prompts && scenario.app.preferences.prompt(for: .custom1) == custom,
                     "A failed save must keep the active library and binding")
    }

    static func waitFor(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Timed out: " + description)
    }

    private static func record(_ scenario: Scenario, attaching: Bool = false) async throws {
        scenario.app.startRecording(mode: .raw, attachingToScreenshot: attaching)
        try await waitFor("recording") { scenario.app.isRecording }
        scenario.app.stopRecording()
        try await waitFor("voice finished") { !scenario.app.busy }
    }

    static func main() async throws {
        let priorDirectory = ProcessInfo.processInfo.environment["TESS_DATA_DIRECTORY"]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Tess-interaction-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if let priorDirectory { setenv("TESS_DATA_DIRECTORY", priorDirectory, 1) } else { unsetenv("TESS_DATA_DIRECTORY") }
            try? FileManager.default.removeItem(at: root)
        }
        try await checkPromptPreferences(root: root)

        // Local notifications exercise production observer routing without sleeping the Mac.
        let interrupted = try Scenario(root: root)
        let center = NSWorkspace.shared.notificationCenter
        for (stop, resume) in [(NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
                               (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification)] {
            interrupted.app.startRecording(mode: .raw)
            try await waitFor("recording before system interruption") { interrupted.app.isRecording }
            let interruptions = interrupted.app.hotkeys.interruptCount
            center.post(name: stop, object: nil)
            try await waitFor("system interruption cancelled recording") {
                !interrupted.app.busy && interrupted.app.hotkeys.interruptCount == interruptions + 1
            }
            precondition(interrupted.app.delivery.delivered.isEmpty)
            precondition(!interrupted.app.hotkeys.suspended)
            let refreshes = interrupted.app.hotkeys.refreshCount
            center.post(name: resume, object: nil)
            try await waitFor("Fn refreshed after system interruption") { interrupted.app.hotkeys.refreshCount == refreshes + 1 }
            precondition(interrupted.app.hotkeys.registerCount == 1, "Recovery must not replace current shortcut registrations")
        }
        // Shortcut recording deliberately suspends hotkeys; sleep/wake must preserve that state.
        interrupted.app.hotkeys.suspend()
        let interruptions = interrupted.app.hotkeys.interruptCount
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await waitFor("interrupted while shortcuts suspended") { interrupted.app.hotkeys.interruptCount == interruptions + 1 }
        let refreshes = interrupted.app.hotkeys.refreshCount
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitFor("wake while shortcuts suspended") { interrupted.app.hotkeys.refreshCount == refreshes + 1 }
        precondition(interrupted.app.hotkeys.suspended && interrupted.app.hotkeys.registerCount == 1)
        interrupted.app.shutdown()

        // Retained targets prove cancel stops tracking before an in-flight delivery returns.
        let tracking = try Scenario(root: root)
        tracking.app.asr.transcripts = [.success("取消前的结果"), .success("重新录音的结果")]
        tracking.app.delivery.holdDelivery = true
        tracking.app.startRecording(mode: .raw)
        try await waitFor("recording before held delivery") { tracking.app.isRecording }
        let cancelledTarget = tracking.app.delivery.capturedTargets[0]
        tracking.app.stopRecording()
        try await waitFor("held target delivery") { tracking.app.delivery.pendingDelivery != nil }
        precondition(cancelledTarget.stopTrackingCount == 0)
        tracking.app.cancel()
        precondition(cancelledTarget.stopTrackingCount == 1 && !tracking.app.busy,
                     "Cancel must synchronously stop tracking even while delivery retains its target")
        precondition(tracking.app.delivery.pendingDelivery != nil)
        tracking.app.delivery.holdDelivery = false
        tracking.app.startRecording(mode: .raw)
        precondition(tracking.app.delivery.capturedTargets.count == 2)
        let nextTarget = tracking.app.delivery.capturedTargets[1]
        precondition(cancelledTarget.stopTrackingCount == 1 && nextTarget.stopTrackingCount == 0)
        try await waitFor("recording after cancelled delivery") { tracking.app.isRecording }
        tracking.app.delivery.completeHeldDelivery()
        try await waitFor("cancelled delivery returned") { tracking.app.delivery.completedDeliveries == 1 }
        precondition(tracking.app.isRecording && nextTarget.stopTrackingCount == 0,
                     "A late delivery must not stop the new target")
        tracking.app.stopRecording()
        try await waitFor("reentered recording finished") { !tracking.app.busy }
        precondition(tracking.app.delivery.capturedTargets.allSatisfy { $0.stopTrackingCount == 1 },
                     "Finish must stop its target without stopping an old target again")
        tracking.app.startRecording(mode: .raw)
        precondition(tracking.app.delivery.capturedTargets.count == 3)
        precondition(tracking.app.delivery.capturedTargets[2].stopTrackingCount == 0)
        tracking.app.cancel()
        precondition(tracking.app.delivery.capturedTargets.allSatisfy { $0.stopTrackingCount == 1 },
                     "Immediate cancellation after recapture must leave no target tracking")
        tracking.app.shutdown()

        // Setup must not succeed from a click, cancellation, silence or a failed recognizer.
        let setup = try Scenario(root: root)
        setup.app.preferences.completedOnboarding = false
        setup.app.preferences.onboardingStep = 0
        setup.app.startRecording()
        precondition(!setup.app.busy && setup.app.recorder.startCount == 0)
        setup.app.preferences.onboardingStep = 3
        setup.app.startRecording()
        try await waitFor("practice recording") { setup.app.isRecording }
        setup.app.cancel()
        precondition(setup.app.preferences.onboardingPracticePassed != true)
        precondition(setup.app.delivery.delivered.isEmpty)
        setup.app.recorder.hasSpeech = false
        try await record(setup)
        precondition(setup.app.preferences.onboardingPracticePassed != true)
        setup.app.recorder.hasSpeech = true
        setup.app.asr.transcripts = [.failure(ASRError.isolatedFailure), .success("真实管线替身结果")]
        try await record(setup)
        precondition(setup.app.preferences.onboardingPracticePassed != true)
        try await record(setup)
        precondition(setup.app.preferences.onboardingPracticePassed == true)
        precondition(setup.app.practiceTranscript == "真实管线替身结果")
        precondition(setup.app.delivery.delivered.isEmpty && !setup.events.contains("hideWindows"))
        precondition(!setup.app.preferences.completedOnboarding, "Practice alone must not complete external-input setup")
        let savedSetup = try JSONDecoder().decode(AppPreferences.self, from: Data(contentsOf: setup.app.directory.appendingPathComponent("preferences.json")))
        precondition(savedSetup.onboardingStep == 3 && savedSetup.onboardingPracticePassed == true)
        setup.app.preferences.onboardingStep = 4
        setup.app.asr.transcripts = [.success("外部输入")]
        try await record(setup)
        precondition(setup.app.delivery.delivered == ["外部输入"])
        setup.app.shutdown()

        // Preview replaces revisions, remains separate from delivery, and final text wins.
        let live = try Scenario(root: root)
        live.app.startRecording(mode: .raw)
        try await waitFor("first live preview") { live.app.liveTranscript == "第一段转录" }
        precondition(live.app.isRecording && live.app.delivery.delivered.isEmpty)
        precondition(live.app.hudSnapshot.transcript == "第一段转录")
        try await waitFor("revised live preview") { live.app.liveTranscript == "第一段修正后的转录" }
        live.app.stopRecording()
        try await waitFor("final live result") { !live.app.busy }
        precondition(live.app.liveTranscript == "隔离语音结果")
        precondition(live.app.delivery.delivered == ["隔离语音结果"])
        live.app.manualText = "新的手动文字"
        live.app.processManual()
        precondition(live.app.hudSnapshot.transcript == "新的手动文字")
        try await waitFor("manual result after voice") { !live.app.busy }
        live.app.editOutput("编辑后的待插入文字")
        live.app.insertManually()
        live.app.confirmInsertion()
        live.app.confirmInsertion()
        precondition(live.app.hudSnapshot.transcript == "编辑后的待插入文字")
        try await waitFor("manual insertion after voice") { !live.app.busy }
        live.app.shutdown()

        // An uncooperative preview response cannot overwrite a new recording.
        let latePreview = try Scenario(root: root)
        latePreview.app.asr.holdPartial = true
        latePreview.app.startRecording(mode: .raw)
        try await waitFor("held live preview") { latePreview.app.asr.pendingPartial != nil }
        latePreview.app.cancel()
        precondition(latePreview.app.liveTranscript.isEmpty && latePreview.app.delivery.delivered.isEmpty)
        latePreview.app.asr.holdPartial = false
        latePreview.app.startRecording(mode: .raw)
        try await waitFor("new live preview") { latePreview.app.liveTranscript == "第一段转录" }
        latePreview.app.asr.completeHeldPartial("已取消会话的迟到文字")
        await Task.yield()
        precondition(latePreview.app.liveTranscript == "第一段转录" && latePreview.app.isRecording)
        latePreview.app.shutdown()

        // Stopping with a preview in flight must never deliver that preview as final text.
        let stoppingPreview = try Scenario(root: root)
        stoppingPreview.app.asr.holdPartial = true
        stoppingPreview.app.startRecording(mode: .raw)
        try await waitFor("preview before stop") { stoppingPreview.app.asr.pendingPartial != nil }
        stoppingPreview.app.stopRecording()
        try await waitFor("final result before stale preview") { !stoppingPreview.app.busy }
        stoppingPreview.app.asr.completeHeldPartial("未完成的旧片段")
        await Task.yield()
        precondition(stoppingPreview.app.liveTranscript == "隔离语音结果")
        precondition(stoppingPreview.app.delivery.delivered == ["隔离语音结果"])
        stoppingPreview.app.shutdown()

        // Existing windows close only after target capture; an old image does not attach implicitly.
        for preview in [false, true] {
            let scenario = try Scenario(root: root)
            scenario.app.preferences.alwaysPreview = preview
            try await record(scenario)
            precondition(Array(scenario.events.prefix(3)) == ["target", "hideWindows", "showHUD"])
            precondition(scenario.app.result?.imageName == nil && scenario.app.result?.origin == "voice")
            precondition(scenario.openedResults == (preview ? 1 : 0))
            precondition(scenario.app.delivery.delivered.count == (preview ? 0 : 1))
            scenario.app.shutdown()
        }

        // Completion feedback closes itself; its timer must not close a new recording HUD.
        let completing = try Scenario(root: root)
        try await record(completing)
        precondition(!completing.events.contains("hideHUD") && completing.openedResults == 0)
        let reentering = try Scenario(root: root)
        try await record(reentering)
        reentering.events.removeAll()
        reentering.app.startRecording(mode: .raw)
        try await waitFor("recording during previous feedback timeout") { reentering.app.isRecording }
        try await Task.sleep(for: .milliseconds(2_600))
        precondition(completing.events.filter { $0 == "hideHUD" }.count == 1 && completing.openedResults == 0,
                     "Voice completion must dismiss its HUD without opening a result window")
        precondition(reentering.app.isRecording && !reentering.events.contains("hideHUD") && reentering.openedResults == 0,
                     "Previous completion timer must not hide a new recording HUD")
        completing.app.shutdown()
        reentering.app.shutdown()

        // Retrying recognition follows normal delivery, while keeping Always preview effective.
        for preview in [false, true] {
            let scenario = try Scenario(root: root)
            scenario.app.preferences.alwaysPreview = preview
            scenario.app.asr.transcripts = [.failure(ASRError.isolatedFailure), .success("隔离重试结果")]
            try await record(scenario)
            precondition(scenario.app.canRetryTranscription && scenario.openedResults == 0)
            scenario.events.removeAll()
            scenario.app.retryFromHUD()
            try await waitFor("recognition retry") { !scenario.app.busy }
            precondition(Array(scenario.events.prefix(3)) == ["target", "hideWindows", "showHUD"])
            precondition(scenario.app.result?.output == "隔离重试结果" && scenario.app.result?.imageName == nil)
            precondition(scenario.openedResults == (preview ? 1 : 0))
            precondition(scenario.app.delivery.delivered.count == (preview ? 0 : 1))
            scenario.app.shutdown()
        }

        let annotation = try Scenario(root: root)
        try await record(annotation, attaching: true)
        precondition(annotation.app.result?.imageName == annotation.old.imageName)
        precondition(annotation.openedResults == 1 && annotation.app.delivery.delivered.isEmpty)
        precondition(!annotation.events.contains("target") && annotation.events.first == "hideWindows")
        precondition(FileManager.default.fileExists(atPath: annotation.oldImage.path))
        annotation.app.shutdown()

        // No-speech failures have no retained audio, so HUD retry starts recording again.
        let silentAnnotation = try Scenario(root: root)
        silentAnnotation.app.recorder.hasSpeech = false
        try await record(silentAnnotation, attaching: true)
        precondition(silentAnnotation.app.hudSnapshot.phase == .failed)
        precondition(!silentAnnotation.app.canRetryTranscription && silentAnnotation.openedResults == 0)
        silentAnnotation.app.recorder.hasSpeech = true
        silentAnnotation.app.retryFromHUD()
        try await waitFor("annotation recording retry") { silentAnnotation.app.isRecording }
        silentAnnotation.app.stopRecording()
        try await waitFor("annotation retry finished") { !silentAnnotation.app.busy }
        precondition(silentAnnotation.app.result?.imageName == silentAnnotation.old.imageName)
        precondition(silentAnnotation.openedResults == 1 && silentAnnotation.app.delivery.delivered.isEmpty)
        silentAnnotation.app.shutdown()

        let cancelled = try Scenario(root: root)
        cancelled.app.takeScreenshot()
        try await waitFor("selection cancelled") { !cancelled.app.busy }
        precondition(cancelled.openedResults == 0 && !cancelled.events.contains("showHUD"))
        precondition(Array(cancelled.events.prefix(2)) == ["hideWindows", "hideHUDImmediately"])
        try cancelled.assertOldContentIntact()
        cancelled.app.shutdown()

        for failure in [CaptureService.Failure.permissionRequired, .captureFailed] {
            let scenario = try Scenario(root: root)
            scenario.app.capture.nextFailure = failure
            scenario.app.takeScreenshot()
            try await waitFor("capture failure") { !scenario.app.busy }
            let hud = scenario.app.hudSnapshot
            precondition(hud.phase == .failed && hud.canRetry && !hud.canShowResult)
            precondition(hud.retryTitle == "重试截图" && (hud.settingsTitle != nil) == (failure == .permissionRequired))
            precondition(scenario.openedResults == 0 && scenario.events.contains("showHUD"))
            try scenario.assertOldContentIntact()
            let newImage = try scenario.newImage()
            scenario.app.capture.nextFailure = nil
            scenario.app.capture.nextURL = newImage
            scenario.app.retryFromHUD()
            try await waitFor("capture retry") { !scenario.app.busy }
            precondition(scenario.app.capture.calls == 2 && scenario.app.recorder.startCount == 0)
            precondition(scenario.openedResults == 1 && scenario.app.result?.imageName == newImage.lastPathComponent)
            precondition(scenario.app.isImageOnlyResult, "A new capture must open the image-only editor")
            let openedBeforeCompletion = scenario.openedResults
            scenario.app.completeScreenshotEditing()
            precondition(scenario.events.last == "hideWindows" && scenario.openedResults == openedBeforeCompletion,
                         "Completing image editing closes the editor without opening a text result")
            precondition(scenario.app.status == "图片已复制，可直接粘贴。" && scenario.app.delivery.delivered.isEmpty)
            scenario.app.shutdown()
        }

        // A cancelled OS response must not replace a newer capture, reopen a window, or leak its file.
        let late = try Scenario(root: root)
        let staleImage = try late.newImage()
        late.app.capture.holdResponse = true
        late.app.takeScreenshot()
        try await waitFor("pending selection") { late.app.capture.pending != nil }
        late.app.cancel()
        try late.assertOldContentIntact()
        precondition(late.openedResults == 0)
        late.app.capture.holdResponse = false
        let latestImage = try late.newImage()
        late.app.capture.nextURL = latestImage
        late.app.takeScreenshot()
        try await waitFor("new selection") { !late.app.busy }
        let latestResultID = late.app.result?.id
        late.app.capture.completeHeld(with: staleImage)
        try await waitFor("late selection discarded") { late.app.capture.deleted.contains(staleImage) }
        precondition(late.app.result?.id == latestResultID && late.app.result?.imageName == latestImage.lastPathComponent)
        precondition(late.openedResults == 1 && !FileManager.default.fileExists(atPath: staleImage.path))
        late.app.shutdown()

        print("Interaction checks passed against production AppModel: immediate target tracking stop on cancellation, finish and recapture with a late delivery retained; sleep/session interruption and recovery with shortcut suspension preserved, live preview revisions, cancellation/reentry and final-only delivery, target-before-hide, voice/retry delivery, timed HUD dismissal and recording reentry, Always preview, explicit image annotation, capture cancellation/failures/retry, and cancelled late capture after reentry. Only isolated files and external-service substitutes used; no microphone, permissions, clipboard, Keychain or API calls.")
    }
}
