import AppKit
import AVFoundation
import Observation

enum SessionPhase: Equatable {
  case idle, loading, recording, transcribing, processing, delivering, capturing, selectingTarget
}

@MainActor @Observable final class AppModel {
  var preferences: AppPreferences
  var recent: SavedResult?
  var draft: SavedResult?
  var phase: SessionPhase = .idle
  var status = ""
  private(set) var liveTranscript = ""
  var hudFeedback: HUDPhase = .completed
  var hudScreenID: CGDirectDisplayID?
  var hudSessionID: UUID? { sessionID }
  var storageNotice: String?
  var manualText = ""
  var showingManualInput = false
  private(set) var isPracticing = false
  private(set) var practiceTranscript = ""
  var settingsSection: SettingsSection = .general
  let configurations: APIConfigurationStore
  let asr: ASRService
  let recorder = AudioRecorder()
  let hotkeys = HotkeyService()
  let capture: CaptureService
  let delivery: DeliveryService
  let textService = TextService()
  let directory: URL
  @ObservationIgnored private let localStore: LocalStore
  @ObservationIgnored private var pendingCaptureDeletions: Set<String> = []
  var storageRecoveryAvailable: Bool { localStore.hasRecoveryFiles || configurations.hasRecoveryFiles }
  var openResult: (() -> Void)?
  var openSettings: (() -> Void)?
  var showHUD: (() -> Void)?
  var hideHUD: (() -> Void)?
  var hideHUDImmediately: (() -> Void)?
  var hideWindows: (() -> Void)?
  private var task: Task<Void, Never>?
  private var liveTranscriptionTask: Task<Void, Never>?
  private var liveTranscriptionUnavailable = false
  private var sessionID: UUID?
  private var target: DeliveryService.Target? { willSet { target?.stopTracking() } }
  private var pendingInsertion: String?
  private var cleanupTimer: Timer?
  private var interruptedObservers: [NSObjectProtocol] = []
  private var snapshot: AppPreferences?
  private var snapshotConfig: APIConfiguration?
  private var snapshotKey: String?
  private var retryAudio: RecordedAudio?
  private var sessionImageName: String?
  private var captureFailure: CaptureService.Failure?
  private var retryExpiry: Task<Void, Never>?
  private var statusHUDTask: Task<Void, Never>?
  @ObservationIgnored private var recordKeyGesture = RecordKeyGesture()
  @ObservationIgnored private var activeRecordAction: ShortcutAction?
  var canRetryTranscription: Bool { retryAudio != nil && !busy }

  var result: SavedResult? { draft ?? recent }
  var isImageOnlyResult: Bool {
    guard let result, result.imageName != nil else { return false }
    return result.original.isEmpty && result.output.isEmpty && (result.candidate?.isEmpty ?? true)
  }
  var busy: Bool { phase != .idle }
  var isRecording: Bool { phase == .recording }
  var isTextProcessing: Bool { phase == .processing && pendingInsertion == nil }
  var activeMode: TextMode { busy ? (snapshot?.textMode ?? preferences.textMode) : preferences.textMode }
  var activeRecognitionLanguage: String { snapshot?.recognitionLanguage ?? preferences.recognitionLanguage }
  private var recordingHint: String {
    guard let action = activeRecordAction else { return tr("说完后点击停止 · Esc 取消", "Press Stop when done · Esc cancels") }
    let settings = snapshot ?? preferences
    if settings.bindings[action]?.isFn == true {
      return tr("松开或再按快捷键结束 · Esc 取消", "Release or press your shortcut again to finish · Esc cancels")
    }
    return settings.holdToRecord
      ? tr("松开快捷键结束 · Esc 取消", "Release your shortcut to finish · Esc cancels")
      : tr("再按快捷键结束 · Esc 取消", "Press your shortcut again to finish · Esc cancels")
  }
  var hudSnapshot: HUDSnapshot {
    let state: HUDPhase
    let title: String
    let detail: String
    switch phase {
    case .loading:
      state = .preparing; title = status
      detail = tr("就绪后即可说话 · Esc 取消", "Speak when ready · Esc cancels")
    case .recording:
      state = .recording; title = tr("正在聆听", "Listening")
      detail = liveTranscriptionUnavailable
        ? tr("实时转录暂不可用，录音仍在继续；结束后识别完整内容。", "Live preview unavailable. Recording continues; the full audio will be transcribed when you stop.")
        : recorder.elapsed >= 270 ? status : recordingHint
    case .transcribing:
      state = .transcribing; title = tr("正在识别语音", "Transcribing speech")
      detail = tr("录下的声音在本机处理", "Audio is processed on this Mac")
    case .processing:
      state = .processing; title = tr("正在整理文字", "Editing text")
      detail = snapshotConfig.map { tr("文字发送至 ", "Text sent to ") + $0.receiver }
        ?? tr("保留原文，检查整理服务", "Keeping the original; checking the text service")
    case .delivering:
      state = .delivering; title = tr("正在输出", "Delivering text")
      detail = tr("核对本次输入位置", "Checking this session’s input position")
    case .selectingTarget:
      state = .selectingTarget; title = tr("选择输入位置", "Choose an input position"); detail = status
    case .capturing:
      state = .preparing; title = tr("选区截图", "Capture selection"); detail = status
    case .idle:
      state = hudFeedback
      if let captureFailure {
        title = captureFailure == .permissionRequired ? tr("截图需要屏幕权限", "Screen permission needed") : tr("截图未完成", "Screenshot failed")
      } else { switch hudFeedback {
      case .copied: title = tr("已复制文字", "Text copied")
      case .failed: title = tr("暂时未能完成", "Couldn’t finish")
      case .cancelled: title = tr("已取消", "Cancelled")
      default: title = tr("文字已准备好", "Text is ready")
      } }
      detail = status
    }
    return HUDSnapshot(phase: state, title: title, subtitle: detail,
                       mode: captureFailure == nil ? modeTitle(snapshot?.textMode ?? .raw, settings: snapshot) : "",
                       elapsed: recorder.elapsed, levels: recorder.levelHistory, isSilent: recorder.isQuiet,
                       canRetry: state == .failed, isEnglish: !preferences.language.usesChinese,
                       includesEditing: (snapshot?.textMode ?? preferences.textMode) != .raw,
                       canShowResult: captureFailure == nil && result != nil,
                       confirmTitle: target == nil ? tr("确认位置", "Confirm destination") : tr("确认粘贴", "Confirm paste"),
                       retryTitle: captureFailure != nil ? tr("重试截图", "Retry capture") : canRetryTranscription ? tr("重试识别", "Retry") : tr("再试一次", "Try again"),
                       settingsTitle: captureFailure == .permissionRequired ? tr("打开设置", "Open Settings") : nil,
                       transcript: [.recording, .transcribing, .processing, .delivering].contains(phase) ? liveTranscript : "")
  }
  var selectedTargetName: String? { target?.applicationName }
  var imageURL: URL? {
    guard let name = result?.imageName, isCaptureName(name) else { return nil }
    return capture.capturesDirectory.appendingPathComponent(name)
  }

  init() {
    #if TESS_INTERNAL_CHECKS
    if let custom = ProcessInfo.processInfo.environment["TESS_DATA_DIRECTORY"] {
      directory = URL(fileURLWithPath: custom, isDirectory: true)
    } else {
      directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tess", isDirectory: true)
    }
    #else
    directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tess", isDirectory: true)
    #endif
    let store = LocalStore(directory: directory)
    localStore = store
    delivery = DeliveryService(diagnosticURL: directory.appendingPathComponent("Diagnostics/input.json"))
    var loadedPreferences = AppPreferences()
    if case .value(let value) = store.read(AppPreferences.self, name: "preferences.json") { loadedPreferences = value }
    loadedPreferences.migrate()
    preferences = loadedPreferences
    if case .value(let value) = store.read(SavedResult?.self, name: "recent.json") { recent = value }
    if case .value(let value) = store.read(SavedResult?.self, name: "draft.json") { draft = value }
    configurations = APIConfigurationStore(storageDirectory: directory)
    asr = ASRService(modelsDirectory: directory.appendingPathComponent("Models", isDirectory: true))
    capture = CaptureService(capturesDirectory: directory.appendingPathComponent("Captures", isDirectory: true))
    if let selected = preferences.asrModel { asr.selectedModel = selected }
    settingsSection = asr.isReady(asr.selectedModel) ? .general : .speech
    recorder.selectedDeviceID = preferences.microphoneID
    if configurations.current?.testStatus != .passed { preferences.textMode = .raw }
    persist(preferences, name: "preferences.json")
    cleanupExpired()
    if draft?.origin == "manual-draft" { manualText = draft?.original ?? ""; showingManualInput = true }
    cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.cleanupExpired() }
    }
    hotkeys.register(preferences.bindings)
    hotkeys.onPress = { [weak self] action, time in
      guard let self else { return }
      switch action {
      case .record, .custom1, .custom2:
        self.handleRecordKey(action, pressed: true, at: time)
      case .screenshot: self.takeScreenshot()
      case .result: self.showResult()
      case .recordLight, .recordList, .recordPolish: break
      }
    }
    hotkeys.onRelease = { [weak self] action, time in
      guard let self, action.recordMode != nil else { return }
      self.handleRecordKey(action, pressed: false, at: time)
    }
    hotkeys.onCancel = { [weak self] in self?.cancel() }
    hotkeys.onRecordInterrupt = { [weak self] action in
      guard let self, self.activeRecordAction == action,
            self.phase == .loading || self.phase == .recording else { return }
      self.cancel()
    }
    recorder.onLimit = { [weak self] in self?.stopRecording() }
    recorder.onWarning = { [weak self] in self?.status = self?.tr("已录音 4 分 30 秒，即将达到上限。", "4:30 recorded. The five-minute limit is approaching.") ?? "" }
    recorder.onError = { [weak self] error in
      guard let self else { return }
      if self.phase == .recording { self.stopRecording() }
      self.status = error.localizedDescription
    }
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
      interruptedObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          self?.cancel()
          self?.hotkeys.interruptForSessionChange()
        }
      })
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
      interruptedObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in self?.hotkeys.refreshFn() }
      })
    }
    interruptedObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.hotkeys.refreshFn() }
    })
    delivery.startDesktopAccessibilityPreparation()
  }

  func tr(_ chinese: String, _ english: String) -> String { preferences.language.usesChinese ? chinese : english }
  func modeTitle(_ mode: TextMode, settings: AppPreferences? = nil) -> String {
    (settings ?? preferences).prompt(for: mode)?.title(chinese: preferences.language.usesChinese)
      ?? tr(mode.title, mode.englishTitle)
  }
  func savePreferences() {
    if configurations.current?.testStatus != .passed { preferences.textMode = .raw }
    preferences.asrModel = asr.selectedModel
    preferences.microphoneID = recorder.selectedDeviceID
    persist(preferences, name: "preferences.json")
  }
  @discardableResult func savePromptLibrary(_ prompts: [TextPrompt]) -> Bool {
    guard !prompts.isEmpty, prompts.allSatisfy(\.isValid), Set(prompts.map(\.id)).count == prompts.count,
          [TextMode.custom1, .custom2].allSatisfy({ mode in
            preferences.prompt(for: mode).map { bound in prompts.contains { $0.id == bound.id } } == true
          }) else { return false }
    var next = preferences
    next.promptLibrary = prompts
    guard persist(next, name: "preferences.json") else { return false }
    preferences = next
    return true
  }
  @discardableResult func setPrompt(_ id: String, for mode: TextMode) -> Bool {
    guard mode.isCustom, preferences.availablePrompts.contains(where: { $0.id == id && $0.isValid }) else { return false }
    var next = preferences
    if mode == .custom1 { next.custom1PromptID = id } else { next.custom2PromptID = id }
    guard persist(next, name: "preferences.json") else { return false }
    preferences = next
    return true
  }
  func setShortcut(_ action: ShortcutAction, binding: ShortcutBinding?) -> Bool {
    guard action != .record || binding == .fn else {
      hotkeys.lastError = tr("基础语音输入固定使用 Fn。", "Basic dictation always uses Fn.")
      return false
    }
    if let binding, preferences.bindings.contains(where: { $0.key != action && $0.value == binding }) {
      hotkeys.lastError = tr("与 Tess 的其他快捷键重复。", "This shortcut is already used by Tess.")
      return false
    }
    let old = preferences.bindings[action]
    guard hotkeys.set(action, binding: binding) else {
      let error = hotkeys.lastError
      _ = hotkeys.set(action, binding: old)
      hotkeys.lastError = error
      return false
    }
    preferences.bindings[action] = binding
    savePreferences()
    return true
  }
  func showResult() { cleanupExpired(); openResult?() }
  func showSettings(_ section: SettingsSection) { settingsSection = section; openSettings?() }

  private func handleRecordKey(_ shortcut: ShortcutAction, pressed: Bool, at time: TimeInterval) {
    guard pressed || activeRecordAction == shortcut else { return }
    let settings = busy ? (snapshot ?? preferences) : preferences
    let automatic = settings.bindings[activeRecordAction ?? shortcut]?.isFn == true
    let state: RecordKeyGesture.Phase
    switch phase { case .idle: state = .idle; case .loading: state = .loading; case .recording: state = .recording; default: state = .busy }
    let action = pressed ? recordKeyGesture.press(at: time, phase: state, automatic: automatic, hold: settings.holdToRecord)
      : recordKeyGesture.release(at: time, phase: state, automatic: automatic, hold: settings.holdToRecord)
    switch action {
    case .start:
      activeRecordAction = shortcut
      startRecording(mode: shortcut.recordMode)
      if !busy { recordKeyGesture.reset(); activeRecordAction = nil }
    case .stop: stopRecording()
    case .cancel: cancel()
    case .none: if pressed, busy { showHUD?() }
    }
  }

  func startRecording(mode: TextMode? = nil, attachingToScreenshot: Bool = false) {
    guard !busy else { if phase != .capturing { showHUD?() }; return }
    if !preferences.completedOnboarding, (preferences.onboardingStep ?? 0) < 3 {
      openResult?()
      return
    }
    let practicing = !preferences.completedOnboarding && preferences.onboardingStep == 3
    statusHUDTask?.cancel()
    captureFailure = nil
    let selectedMode = practicing ? TextMode.raw : (mode ?? .raw)
    guard !selectedMode.isCustom || preferences.prompt(for: selectedMode)?.isValid == true else {
      status = tr("请先为这个自定义快捷键选择提示词。", "Choose a prompt for this custom shortcut first.")
      showSettings(.general)
      return
    }
    guard selectedMode == .raw || configurations.current?.testStatus == .passed else {
      status = tr("请先配置并测试文字服务，再使用整理快捷键。", "Configure and test a text service before using an editing shortcut.")
      hideHUD?()
      showSettings(.text)
      return
    }
    guard asr.isReady(asr.selectedModel) else {
      status = tr("请先在设置中下载一个本地语音模型。", "Download a local speech model in Settings first.")
      hideHUD?()
      showSettings(.speech)
      return
    }
    isPracticing = practicing
    let id = UUID()
    liveTranscript = ""
    liveTranscriptionUnavailable = false
    hudFeedback = .preparing
    retryAudio = nil; retryExpiry?.cancel()
    sessionID = id
    showingManualInput = false
    sessionImageName = attachingToScreenshot ? result?.imageName : nil
    let binding = activeRecordAction.flatMap { preferences.bindings[$0] }
    target = !isPracticing && sessionImageName == nil
      ? delivery.captureTarget(compatibilityShortcut: binding.map { ($0.keyCode, $0.modifiers) }) : nil
    hudScreenID = target?.screenID
    if !isPracticing { hideWindows?() }
    snapshot = preferences
    snapshot?.textMode = selectedMode
    snapshot?.asrModel = asr.selectedModel
    snapshotConfig = configurations.current.flatMap { $0.testStatus == .passed ? $0 : nil }
    snapshotKey = nil
    if selectedMode != .raw, let configuration = snapshotConfig {
      snapshotKey = try? configurations.apiKey(for: configuration)
    }
    phase = .loading
    status = tr("正在加载语音模型…", "Loading speech model…")
    hotkeys.enableEscape(true)
    showHUD?()
    task = Task { [weak self] in
      guard let self else { return }
      do {
        try await self.asr.prepare(model: self.snapshot?.asrModel)
        guard self.sessionID == id, !Task.isCancelled else { return }
        self.status = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
          ? self.tr("请在系统提示中允许麦克风访问", "Allow microphone access in the system prompt")
          : self.tr("正在准备麦克风…", "Preparing microphone…")
        self.asr.setRecording(true)
        try await self.recorder.start(sessionID: id)
        guard self.sessionID == id, !Task.isCancelled else { self.recorder.cancel(sessionID: id); return }
        self.phase = .recording
        self.status = self.tr("正在聆听", "Listening")
        self.startLiveTranscription(id: id)
      } catch {
        guard self.sessionID == id else { return }
        self.finish(error.localizedDescription, showResult: false, feedback: .failed)
      }
    }
  }

  private func startLiveTranscription(id: UUID) {
    liveTranscriptionTask?.cancel()
    let language = snapshot?.recognitionLanguage ?? "auto"
    let model = snapshot?.asrModel
    liveTranscriptionTask = Task { [weak self] in
      var failures = 0
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
        guard let self, self.sessionID == id, self.phase == .recording else { return }
        guard let audio = self.recorder.snapshot(sessionID: id) else { continue }
        do {
          let partial = try await self.asr.transcribePartial(audio, sessionID: id,
                                                           language: language == "auto" ? nil : language, model: model)
          guard self.sessionID == id, self.phase == .recording, !Task.isCancelled else { return }
          let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
          if !text.isEmpty { self.liveTranscript = text }
          failures = 0
          self.liveTranscriptionUnavailable = false
        } catch is CancellationError { return }
        catch ASRError.silence { continue }
        catch {
          guard self.sessionID == id, self.phase == .recording, !Task.isCancelled else { return }
          failures += 1
          self.liveTranscriptionUnavailable = failures >= 2
        }
      }
    }
  }

  private func stopLiveTranscription() {
    liveTranscriptionTask?.cancel()
    liveTranscriptionTask = nil
    asr.cancelPartialTranscription()
  }

  func stopRecording() {
    guard phase == .recording, let id = sessionID, let audio = recorder.stop() else { return }
    stopLiveTranscription()
    recordKeyGesture.reset()
    recorder.cancel()
    guard audio.hasSpeech else {
      finish(tr("未检测到有效语音，请再试一次。", "No speech detected. Try again."), showResult: false, feedback: .failed)
      return
    }
    retryAudio = audio
    retryExpiry?.cancel()
    retryExpiry = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(600)) } catch { return }
      self?.retryAudio = nil
    }
    phase = .transcribing
    status = tr("正在转写…", "Transcribing…")
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let language = self.snapshot?.recognitionLanguage ?? "auto"
        let transcript = try await self.asr.transcribe(audio, sessionID: id, language: language == "auto" ? nil : language, model: self.snapshot?.asrModel)
        guard self.sessionID == id, !Task.isCancelled else { return }
        let original = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { self.finish(self.tr("未取得有效转写。", "No transcript was produced."), showResult: false, feedback: .failed); return }
        self.liveTranscript = original
        self.retryAudio = nil; self.retryExpiry?.cancel()
        if self.isPracticing {
          self.practiceTranscript = original
          self.preferences.onboardingPracticePassed = true
          self.savePreferences()
          self.finish(self.tr("试说成功。请确认文字，再试一次外部输入。", "Practice complete. Review the text, then try another app."), showResult: true)
          return
        }
        let mode = self.snapshot?.textMode ?? .raw
        self.replaceDraft(SavedResult(original: original, output: original, imageName: self.sessionImageName,
                                      mode: mode, origin: self.sessionImageName == nil ? "voice" : "screenshot"))
        guard self.persistResult() else { self.finish(self.status, showResult: true, feedback: .failed); return }
        await self.processCurrent(id: id, automatic: true)
      } catch {
        guard self.sessionID == id else { return }
        self.finish(error.localizedDescription, showResult: false, feedback: .failed)
      }
    }
  }

  func retryTranscription() {
    guard !busy, let audio = retryAudio else { return }
    statusHUDTask?.cancel()
    captureFailure = nil
    let id = UUID(); sessionID = id
    target = sessionImageName == nil ? delivery.captureTarget() : nil
    hudScreenID = target?.screenID
    hideWindows?()
    showingManualInput = false
    phase = .transcribing
    status = tr("正在重试识别…", "Retrying transcription…")
    hotkeys.enableEscape(true); showHUD?()
    snapshotKey = snapshot?.textMode == .raw ? nil : snapshotConfig.flatMap { try? configurations.apiKey(for: $0) }
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let language = self.snapshot?.recognitionLanguage ?? "auto"
        let transcript = try await self.asr.transcribe(audio.withSessionID(id), sessionID: id, language: language == "auto" ? nil : language, model: self.snapshot?.asrModel)
        guard self.sessionID == id, !Task.isCancelled else { return }
        let original = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { throw ASRError.silence }
        self.liveTranscript = original
        self.retryAudio = nil; self.retryExpiry?.cancel()
        self.replaceDraft(SavedResult(original: original, output: original, imageName: self.sessionImageName,
                                      mode: self.snapshot?.textMode ?? .raw, origin: self.sessionImageName == nil ? "voice" : "screenshot"))
        guard self.persistResult() else { self.finish(self.status, showResult: true, feedback: .failed); return }
        await self.processCurrent(id: id, automatic: true)
      } catch {
        guard self.sessionID == id else { return }
        self.finish(error.localizedDescription, showResult: false, feedback: .failed)
      }
    }
  }

  func retryFromHUD() {
    guard !busy else { return }
    if captureFailure != nil { takeScreenshot() }
    else if canRetryTranscription { retryTranscription() }
    else { startRecording(mode: snapshot?.textMode, attachingToScreenshot: sessionImageName != nil) }
  }

  func processManual() {
    guard !busy else { return }
    let original = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !original.isEmpty else { return }
    replaceDraft(SavedResult(original: original, output: original, mode: preferences.textMode, origin: "manual"))
    guard persistResult() else { return }
    showingManualInput = false
    beginProcessing()
  }

  func reprocess() {
    guard !busy, var current = result, !current.original.isEmpty else { return }
    current.mode = preferences.textMode
    current.output = current.original; current.candidate = nil; current.message = nil
    replaceDraft(current)
    guard persistResult() else { return }
    beginProcessing()
  }

  private func beginProcessing() {
    captureFailure = nil
    liveTranscript = draft?.original ?? ""
    retryAudio = nil; retryExpiry?.cancel()
    let id = UUID(); sessionID = id
    phase = .processing
    snapshot = preferences; snapshotConfig = configurations.current.flatMap { $0.testStatus == .passed ? $0 : nil }
    snapshotKey = preferences.textMode == .raw ? nil : snapshotConfig.flatMap { try? configurations.apiKey(for: $0) }
    hotkeys.enableEscape(true)
    task = Task { [weak self] in await self?.processCurrent(id: id, automatic: false) }
  }

  private func processCurrent(id: UUID, automatic: Bool) async {
    guard let current = draft else { return }
    let mode = current.mode
    if mode != .raw {
      phase = .processing
      status = tr("正在处理文字…", "Processing text…")
      let processed = await textService.process(current.original, mode: mode, configuration: snapshotConfig, apiKey: snapshotKey,
                                               prompts: snapshot?.textPrompts ?? TextPrompts(), prompt: snapshot?.prompt(for: mode))
      guard sessionID == id, !Task.isCancelled, !processed.isCancelled else { return }
      draft?.output = processed.output
      draft?.candidate = processed.candidate
      draft?.message = processed.error?.message ?? processed.warnings.joined(separator: "\n")
    }
    guard sessionID == id, !Task.isCancelled, let completed = draft else { return }
    replaceRecent(completed)
    guard persistResult() else {
      finish(tr("结果尚未保存，请先在面板复制并检查存储空间。", "The result could not be saved. Copy it from the panel and check free space."), showResult: true, feedback: .failed)
      return
    }
    let preview = !automatic || completed.imageName != nil || snapshot?.alwaysPreview == true
    if !preview {
      phase = .delivering
      status = tr("正在输出…", "Delivering text…")
      let outcome = await delivery.deliverVoice(text: completed.output, target: target)
      guard sessionID == id, !Task.isCancelled else { return }
      var message = deliveryMessage(outcome)
      if completed.mode != .raw, completed.message?.isEmpty == false, completed.output == completed.original {
        message = tr("本次使用原文。", "Using the original transcript. ") + message
      }
      finish(message, showResult: outcome.isUnavailable, showStatus: true,
             feedback: outcome.isCopied ? .copied : outcome.isUnavailable ? .failed : .completed)
    } else { finish(completed.message ?? tr("结果已保留，请检查后使用。", "Result saved. Review before using."), showResult: true) }
    if completed.imageName == nil { replaceDraft(nil); persistResult() }
  }

  func useOriginal() {
    guard !busy || isTextProcessing else { return }
    if isTextProcessing { task?.cancel(); finish("", showResult: false) }
    guard var current = result else { return }
    current.output = current.original
    current.mode = .raw
    current.candidate = nil
    current.message = tr("已切换为原文；已有输入请手动替换。", "Original restored. Replace any previous input manually.")
    if draft != nil { draft = current } else { recent = current }
    status = current.message ?? ""
    persistResult()
  }

  func editOutput(_ text: String) {
    guard !busy else { return }
    if draft != nil { draft?.output = text } else { recent?.output = text }
    persistResult()
  }
  func copyResult() {
    guard let result, !result.output.isEmpty else { return }
    status = delivery.copyText(result.output) ? tr("已复制文字", "Text copied") : tr("复制失败", "Copy failed")
  }
  func insertManually() {
    guard !busy, let text = result?.output, !text.isEmpty else { return }
    statusHUDTask?.cancel()
    captureFailure = nil
    phase = .selectingTarget
    sessionID = UUID(); target = nil; pendingInsertion = text
    liveTranscript = text
    hudScreenID = nil
    hideWindows?()
    status = tr("请点击目标输入框，再点这里的“确认位置”。", "Click the destination field, then choose Confirm destination here.")
    showHUD?()
    hotkeys.enableEscape(true)
  }
  func confirmInsertion() {
    guard phase == .selectingTarget, let id = sessionID, let text = pendingInsertion else { return }
    guard let target else {
      self.target = delivery.captureTarget()
      status = self.target.map { tr("接收应用：\($0.applicationName)。确认后粘贴。", "Destination: \($0.applicationName). Confirm to paste.") }
        ?? tr("无法确认输入位置。请定位可编辑输入框，或取消后复制文字。", "Cannot confirm the field. Focus an editable field, or cancel and copy the text.")
      return
    }
    phase = .delivering
    status = tr("正在粘贴…", "Pasting…")
    task = Task { [weak self] in
      guard let self, self.sessionID == id, !Task.isCancelled else { return }
      let outcome = await self.delivery.paste(text: text, target: target)
      guard self.sessionID == id else { return }
      self.finish(self.deliveryMessage(outcome), showResult: outcome.isUnavailable, showStatus: true,
                  feedback: outcome.isUnavailable ? .failed : .completed)
    }
  }

  func takeScreenshot() {
    guard !busy else { status = tr("请先结束当前操作。", "Finish the current operation first."); return }
    statusHUDTask?.cancel()
    captureFailure = nil
    phase = .capturing
    let id = UUID(); sessionID = id
    hideWindows?(); hideHUDImmediately?()
    task = Task { [weak self] in
      guard let self else { return }
      guard let url = await self.capture.captureSelection() else {
        guard self.sessionID == id, !Task.isCancelled else { return }
        if let failure = self.capture.failure {
          self.finishCaptureFailure(failure)
        } else {
          self.finish(self.tr("已取消截图", "Screenshot cancelled"), showResult: false)
        }
        return
      }
      guard self.sessionID == id, !Task.isCancelled else { self.capture.delete(url); return }
      self.showingManualInput = false
      self.retryAudio = nil; self.retryExpiry?.cancel()
      self.replaceDraft(SavedResult(original: "", output: "", imageName: url.lastPathComponent, mode: self.preferences.textMode, origin: "screenshot"))
      guard self.persistResult() else { self.finish(self.status, showResult: true); return }
      self.finish(self.tr("圈选或添加文字，按回车完成并复制。", "Mark up the image, then press Return to finish and copy."), showResult: true)
    }
  }
  func completeScreenshotEditing() {
    guard !busy, isImageOnlyResult else { return }
    status = tr("图片已复制，可直接粘贴。", "Image copied. Ready to paste.")
    hideWindows?()
  }
  func finishCaptureFailure(_ failure: CaptureService.Failure) {
    captureFailure = failure
    let message = failure == .permissionRequired
      ? tr("在系统设置中允许 Tess 录制屏幕后重试。若已开启，请退出并重新打开 Tess。", "Allow Tess to record the screen in System Settings, then retry. If already enabled, quit and reopen Tess.")
      : capture.lastError ?? tr("请重新选择截图区域。", "Try selecting an area again.")
    finish(message, showResult: false, feedback: .failed)
  }
  func openScreenCaptureSettings() {
    hideHUDImmediately?()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }
  }
  func removeImage() {
    guard !busy, let url = imageURL else { return }
    if draft?.imageName == url.lastPathComponent { draft?.imageName = nil }
    if recent?.imageName == url.lastPathComponent { recent?.imageName = nil }
    deleteUnreferencedImage(url.lastPathComponent)
    persistResult()
  }
  func newText() {
    guard !busy else { return }
    retryAudio = nil; retryExpiry?.cancel()
    if draft?.origin == "manual-draft" { manualText = draft?.original ?? "" }
    else {
      manualText = ""
      replaceDraft(SavedResult(original: "", output: "", mode: preferences.textMode, origin: "manual-draft"))
      persistResult()
    }
    showingManualInput = true; showResult()
  }
  func editManualText(_ text: String) {
    guard !busy, showingManualInput else { return }
    manualText = text
    draft?.original = text; draft?.output = text
    persistResult()
  }
  func closeManualInput() {
    showingManualInput = false
    if manualText.isEmpty { replaceDraft(nil); persistResult() }
  }

  func cancel() {
    recordKeyGesture.reset()
    activeRecordAction = nil
    statusHUDTask?.cancel()
    captureFailure = nil
    guard busy else { hideHUD?(); return }
    sessionID = nil; task?.cancel(); task = nil
    stopLiveTranscription()
    liveTranscript = ""
    isPracticing = false
    recorder.cancel(); asr.cancel(); capture.cancel()
    asr.setRecording(false)
    retryAudio = nil; retryExpiry?.cancel(); snapshotKey = nil; target = nil; pendingInsertion = nil
    phase = .idle
    status = tr("已取消，已完成的文字仍可恢复。", "Cancelled. Completed text remains available.")
    hudFeedback = .cancelled
    hotkeys.enableEscape(false); persistResult()
    showHUD?()
    dismissFeedback(after: 0.8)
  }
  func shutdown() { cancel(); retryAudio = nil; retryExpiry?.cancel(); savePreferences(); persistResult(); hotkeys.suspend() }
  func clearTemporaryContent() {
    cancel()
    retryAudio = nil; retryExpiry?.cancel()
    for current in [recent, draft].compactMap({ $0 }) {
      if let name = current.imageName, isCaptureName(name) { pendingCaptureDeletions.insert(name) }
    }
    recent = nil; draft = nil; manualText = ""; showingManualInput = false; persistResult()
    status = tr("已清除暂存结果和截图。", "Temporary results and screenshots cleared.")
  }

  private func finish(_ message: String, showResult: Bool, showStatus: Bool = false, feedback: HUDPhase = .completed) {
    recordKeyGesture.reset()
    activeRecordAction = nil
    statusHUDTask?.cancel()
    stopLiveTranscription()
    let wasPracticing = isPracticing
    if wasPracticing { retryAudio = nil; retryExpiry?.cancel() }
    isPracticing = false
    phase = .idle; sessionID = nil; task = nil; snapshotKey = nil; target = nil; pendingInsertion = nil
    asr.setRecording(false)
    status = message; hudFeedback = feedback; hotkeys.enableEscape(false)
    if showResult || wasPracticing { hideHUD?(); openResult?() }
    else if showStatus || feedback == .failed {
      showHUD?()
      dismissFeedback(after: feedback == .failed ? 8 : 2.4)
    } else { hideHUD?() }
  }

  private func dismissFeedback(after seconds: Double) {
    statusHUDTask?.cancel()
    statusHUDTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
      guard let self, !self.busy else { return }
      self.hideHUD?()
    }
  }

  private func deliveryMessage(_ outcome: DeliveryService.Outcome) -> String {
    switch outcome {
    case .attemptedPaste: tr("已尝试粘贴，请在目标应用确认。", "Paste attempted. Check the destination app.")
    case .copiedToClipboard:
      (delivery.failureDescription(chinese: preferences.language.usesChinese).map { $0 + tr("。", ". ") } ?? "")
        + tr("已复制，回到输入框后按 ⌘V 粘贴。", "Copied. Return to the text field and press ⌘V.")
    case .unavailable(let message): message
    }
  }
  @discardableResult private func persistResult() -> Bool {
    let saved = localStore.writeResults(recent: recent, draft: draft) {
      for name in pendingCaptureDeletions where name != draft?.imageName && name != recent?.imageName {
        capture.delete(capture.capturesDirectory.appendingPathComponent(name))
      }
      pendingCaptureDeletions.removeAll()
    }
    updateStorageNotice()
    if !saved { status = tr("本地保存失败，当前结果仍在面板中。", "Local save failed. The result is still in the panel.") }
    return saved
  }
  private func replaceDraft(_ value: SavedResult?) {
    let oldImage = draft?.imageName
    draft = value
    deleteUnreferencedImage(oldImage)
  }
  private func replaceRecent(_ value: SavedResult?) {
    let oldImage = recent?.imageName
    recent = value
    deleteUnreferencedImage(oldImage)
  }
  private func deleteUnreferencedImage(_ name: String?) {
    guard let name, isCaptureName(name), name != draft?.imageName, name != recent?.imageName else { return }
    pendingCaptureDeletions.insert(name)
  }
  private func cleanupExpired() {
    guard !busy else { return }
    var changed = false
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    for isDraft in [false, true] {
      let value = isDraft ? draft : recent
      if let value, value.createdAt < cutoff {
        if isDraft { draft = nil } else { recent = nil }
        deleteUnreferencedImage(value.imageName)
        if isDraft, value.origin == "manual-draft" { manualText = ""; showingManualInput = false }
        changed = true
      }
    }
    if let files = try? FileManager.default.contentsOfDirectory(at: capture.capturesDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
      for file in files where isCaptureName(file.lastPathComponent) {
        if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified < cutoff {
          if draft?.imageName == file.lastPathComponent { draft?.imageName = nil; changed = true }
          if recent?.imageName == file.lastPathComponent { recent?.imageName = nil; changed = true }
          pendingCaptureDeletions.insert(file.lastPathComponent)
          changed = true
        }
      }
    }
    if changed { persistResult() }
  }
  private func isCaptureName(_ name: String) -> Bool {
    name.hasSuffix(".png") && UUID(uuidString: String(name.dropLast(4))) != nil
  }
  @discardableResult private func persist<T: Encodable>(_ value: T, name: String) -> Bool {
    do {
      try localStore.write(value, name: name)
      updateStorageNotice()
      return true
    } catch {
      updateStorageNotice()
      status = tr("本地保存失败，当前结果仍在面板中。", "Local save failed. The result is still in the panel.")
      return false
    }
  }
  func retryLocalSave() {
    configurations.retryLocalSave()
    savePreferences()
    persistResult()
  }
  func revealStorageRecovery() {
    guard storageRecoveryAvailable else { return }
    NSWorkspace.shared.open(localStore.recoveryDirectory)
  }
  private func updateStorageNotice() {
    if !localStore.failedWrites.isEmpty || configurations.hasSaveFailure {
      storageNotice = tr("本地保存失败，当前内容仍在面板中。请先复制重要文字，检查可用空间后重试保存。",
                         "Local save failed. Your current content remains in the panel. Copy important text, check free space, then retry saving.")
    } else if !localStore.unreadableNames.isEmpty || configurations.hasUnreadableFiles {
      storageNotice = tr("部分本地内容无法读取，原文件尚未改动。重试保存前会先保留恢复副本。",
                         "Some local content could not be read. Original files are unchanged; retrying will preserve recovery copies before saving.")
    } else if storageRecoveryAvailable {
      storageNotice = tr("已保留本地恢复文件，请查看后处理。文件中的内容不会自动加入最近结果。",
                         "Local recovery files are preserved for your review. Their content is not automatically added to recent results.")
    } else { storageNotice = nil }
  }
}

extension DeliveryService.Outcome {
  var isUnavailable: Bool { if case .unavailable = self { return true }; return false }
  var isCopied: Bool { if case .copiedToClipboard = self { return true }; return false }
}
