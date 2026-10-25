import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Observation

@MainActor @Observable
final class DeliveryService {
    struct Target {
        let processID: pid_t
        let applicationName: String
        let screenID: CGDirectDisplayID?
        fileprivate enum Location {
            case input(AXUIElement, role: String, range: CFRange)
            case weChatWindow(AXUIElement, InputInteractionGuard)
            case chatGPTWindow(CGWindowID, InputInteractionGuard)
        }
        fileprivate let location: Location

        @MainActor func stopTracking() {
            switch location {
            case .input: break
            case .weChatWindow(_, let interaction), .chatGPTWindow(_, let interaction): interaction.stop()
            }
        }
    }

    enum Outcome {
        case attemptedPaste
        case copiedToClipboard
        case unavailable(String)

        var description: String {
            switch self {
            case .attemptedPaste: "已尝试粘贴，请在目标应用确认。"
            case .copiedToClipboard: "已复制，回到输入框后按 ⌘V 粘贴。"
            case .unavailable(let reason): reason
            }
        }
    }

    struct DiagnosticEvent: Codable {
        let time: Date
        let session: UUID
        let applicationID: String?
        let build: String
        let code: String
        let axError: Int32?
        let role: String?
        let failure: Bool
        let windowID: CGWindowID?
    }

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let diagnosticURL: URL?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    private(set) var diagnosticEvents: [DiagnosticEvent] = []
    private(set) var lastFailure: String?
    private var diagnosticSession = UUID()
    private var diagnosticApplicationID: String?
    private var pasteInProgress = false

    init(pasteboard: NSPasteboard = .general, diagnosticURL: URL? = nil) {
        self.pasteboard = pasteboard
        self.diagnosticURL = diagnosticURL
        if let diagnosticURL, let data = try? Data(contentsOf: diagnosticURL),
           let events = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
            diagnosticEvents = Array(events.suffix(100))
            lastFailure = events.last(where: { $0.session == events.last?.session && $0.failure })?.code
        }
    }

    func startDesktopAccessibilityPreparation() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            _ = MainActor.assumeIsolated { Self.prepareDesktopAccessibility(app) }
        }
        if let app = NSWorkspace.shared.frontmostApplication { Self.prepareDesktopAccessibility(app) }
    }

    // Electron builds its AX tree on demand. Prewarm on activation so the first Fn
    // capture does not race renderer initialization. This neither reads nor edits text.
    @discardableResult private static func prepareDesktopAccessibility(_ app: NSRunningApplication) -> AXError? {
        return prepareDesktopAccessibility(applicationID: app.bundleIdentifier) { attribute in
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.25)
            return AXUIElementSetAttributeValue(application, attribute as CFString, kCFBooleanTrue)
        }
    }

    static func prepareDesktopAccessibility(applicationID: String?, setAttribute: (String) -> AXError) -> AXError? {
        guard ["com.openai.codex", "com.openai.chat"].contains(applicationID ?? "") else { return nil }
        return setAttribute("AXManualAccessibility")
    }

    var diagnosticReport: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(diagnosticEvents)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    func failureDescription(chinese: Bool) -> String? {
        let messages: [String: (String, String)] = [
            "permission_missing": ("辅助功能未授权", "Accessibility access is missing"),
            "secure_input": ("系统安全输入已开启", "Secure input is enabled"),
            "no_application": ("未找到接收应用", "No destination app was found"),
            "tess_frontmost": ("录音开始时 Tess 在前台", "Tess was frontmost when recording began"),
            "terminal": ("终端不支持自动输入", "Automatic input is disabled in terminals"),
            "focus_unavailable": ("未识别到输入框", "The focused field could not be identified"),
            "role_unsupported": ("当前位置不是可编辑输入框", "The focused item is not an editable field"),
            "input_disabled": ("无法确认输入框已启用", "The field could not be confirmed as enabled"),
            "secure_field": ("当前位置是密码或终端输入框", "The focused field is secure or a terminal"),
            "value_not_writable": ("输入框未提供可写状态", "The field does not expose a writable value"),
            "selection_unavailable": ("无法读取光标位置", "The caret position could not be read"),
            "application_changed": ("接收应用已变化", "The destination app changed"),
            "input_changed": ("输入框已变化", "The focused field changed"),
            "selection_changed": ("光标或选区已变化", "The caret or selection changed"),
            "window_changed": ("接收窗口已变化", "The destination window changed"),
            "interaction_changed": ("录音期间发生了其他操作", "Another interaction occurred during recording"),
            "tracking_unavailable": ("无法保护原输入位置", "The original input position could not be protected"),
            "window_unavailable": ("无法识别接收窗口", "The destination window could not be identified")
        ]
        guard let lastFailure, let message = messages[lastFailure] else { return nil }
        return chinese ? message.0 : message.1
    }

    private func note(_ code: String, error: AXError? = nil, role: String? = nil, failure: Bool = false, windowID: CGWindowID? = nil) {
        if failure { lastFailure = code }
        diagnosticEvents.append(DiagnosticEvent(time: Date(), session: diagnosticSession,
            applicationID: diagnosticApplicationID, build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "check",
            code: code, axError: error?.rawValue, role: role, failure: failure, windowID: windowID))
        diagnosticEvents = Array(diagnosticEvents.suffix(100))
        if let diagnosticURL, let data = try? JSONEncoder().encode(diagnosticEvents) {
            try? FileManager.default.createDirectory(at: diagnosticURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: diagnosticURL, options: .atomic)
        }
    }

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Called only when the user starts a recording or explicitly selects an input target.
    func captureTarget(compatibilityShortcut: (keyCode: UInt32, modifiers: UInt32)? = nil) -> Target? {
        diagnosticSession = UUID()
        diagnosticApplicationID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lastFailure = nil
        note("capture_started")
        guard hasAccessibilityPermission else { note("permission_missing", failure: true); return nil }
        guard !IsSecureEventInputEnabled() else { note("secure_input", failure: true); return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { note("no_application", failure: true); return nil }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { note("tess_frontmost", failure: true); return nil }
        guard !isTerminal(app) else { note("terminal", failure: true); return nil }
        if let error = Self.prepareDesktopAccessibility(app) { note("desktop_accessibility_requested", error: error) }
        let focus = focusedElementResult(processID: app.processIdentifier)
        if let element = focus.element {
            guard let role = editableRole(element), let range = selectedRange(element) else { return nil }
            note("input_captured", role: role)
            return Target(processID: app.processIdentifier, applicationName: app.localizedName ?? "",
                          screenID: screenID(for: element), location: .input(element, role: role, range: range))
        }
        // This ChatGPT build returns AX noValue for focus and exposes no AX window.
        // Like WeChat, it needs an explicit, interaction-guarded compatibility target.
        // Window Server metadata provides only identity/bounds, never text or pixels.
        if let compatibilityShortcut, Self.allowsChatGPTWindowCompatibility(applicationID: app.bundleIdentifier,
            hasFocusedElement: false, error: focus.error) {
            guard let window = visibleWindow(processID: app.processIdentifier) else {
                note("window_unavailable", error: focus.error, failure: true); return nil
            }
            let interaction = InputInteractionGuard(processID: app.processIdentifier, shortcut: compatibilityShortcut)
            guard interaction.start() else { note("tracking_unavailable", failure: true); return nil }
            note("chatgpt_window_captured", error: focus.error, windowID: window.id)
            return Target(processID: app.processIdentifier, applicationName: app.localizedName ?? "",
                          screenID: screenID(for: window.center), location: .chatGPTWindow(window.id, interaction))
        }
        // WeChat 4.1 exposes its window but no input element. This explicit compatibility
        // target cannot verify input type or selection; never use it for other applications
        // or when an accessible input was found but failed the normal checks.
        guard let compatibilityShortcut, app.bundleIdentifier == "com.tencent.xinWeChat",
              focus.error == .noValue || focus.error == .attributeUnsupported else {
            note("focus_unavailable", error: focus.error, failure: true); return nil
        }
        guard let window = focusedWindow(processID: app.processIdentifier) else { note("window_unavailable", failure: true); return nil }
        let interaction = InputInteractionGuard(processID: app.processIdentifier, shortcut: compatibilityShortcut)
        guard interaction.start() else { note("tracking_unavailable", failure: true); return nil }
        note("wechat_window_captured")
        return Target(processID: app.processIdentifier, applicationName: app.localizedName ?? "",
                      screenID: screenID(for: window), location: .weChatWindow(window, interaction))
    }

    func deliverVoice(text: String, target: Target?) async -> Outcome {
        guard !text.isEmpty else { return .unavailable("没有可插入的文字。") }
        guard !Task.isCancelled else { return .unavailable("已取消输入。") }
        guard let target, targetIsValid(target) else {
            note("copied_fallback")
            return copyText(text) ? .copiedToClipboard : .unavailable("复制失败，文字已保留，请从最近结果重试。")
        }
        // A failed paste may mean the clipboard changed or could not be preserved.
        // Do not bypass that protection by replacing it with an automatic copy.
        return await paste(text: text, target: target)
    }

    func paste(text: String, target: Target?) async -> Outcome {
        defer { target?.stopTracking() }
        guard !text.isEmpty else { return .unavailable("没有可插入的文字。") }
        guard !Task.isCancelled, let target, targetIsValid(target) else {
            return .unavailable("原输入位置已变化或无法确认，请定位输入框后复制文字。")
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            return .unavailable("无法模拟粘贴，请复制文字。")
        }
        return await pasteUsingClipboard(text: text, validateTarget: { self.targetIsValid(target) }) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            self.note("paste_posted")
            down.postToPid(target.processID)
            up.postToPid(target.processID)
        }
    }

    // The clipboard transaction is separate from system targeting so its recovery can be checked
    // with an isolated pasteboard, without posting keys to any application.
    func pasteUsingClipboard(text: String, validateTarget: () -> Bool, postPaste: () -> Void) async -> Outcome {
        // A cancelled session may still be in the clipboard consumer window.
        // Wait for restoration before the next session captures its clipboard snapshot.
        while pasteInProgress {
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch { return .unavailable("已取消输入。") }
        }
        guard !text.isEmpty, !Task.isCancelled, validateTarget() else {
            return .unavailable("原输入位置已变化或无法确认，请定位输入框后复制文字。")
        }
        pasteInProgress = true
        defer { pasteInProgress = false }
        // Only the actual insertion reads the clipboard, briefly, to restore every recoverable type.
        let originalChangeCount = pasteboard.changeCount
        var snapshot: [NSPasteboardItem] = []
        var byteCount = 0
        let originalItems = pasteboard.pasteboardItems
        guard originalItems != nil || (pasteboard.types ?? []).isEmpty else {
            return .unavailable("当前剪贴板内容无法安全恢复，请使用复制文字。")
        }
        for original in originalItems ?? [] {
            let item = NSPasteboardItem()
            for type in original.types {
                guard let data = original.data(forType: type) else {
                    return .unavailable("当前剪贴板内容无法安全恢复，请使用复制文字。")
                }
                byteCount += data.count
                guard byteCount <= 32 * 1_024 * 1_024 else {
                    return .unavailable("当前剪贴板内容较大，请使用复制文字。")
                }
                guard item.setData(data, forType: type) else {
                    return .unavailable("当前剪贴板内容无法安全恢复，请使用复制文字。")
                }
            }
            snapshot.append(item)
        }
        guard pasteboard.changeCount == originalChangeCount, !Task.isCancelled, validateTarget() else {
            return .unavailable("输入位置或剪贴板已变化，请复制文字。")
        }
        pasteboard.clearContents()
        let written = pasteboard.setString(text, forType: .string)
        let insertionChangeCount = pasteboard.changeCount
        // The user may copy something new while the destination consumes this paste.
        defer {
            if pasteboard.changeCount == insertionChangeCount {
                pasteboard.clearContents()
                if !snapshot.isEmpty { _ = pasteboard.writeObjects(snapshot) }
            }
        }
        guard written, !Task.isCancelled, validateTarget() else {
            return .unavailable("未能安全粘贴，请复制文字。")
        }
        postPaste()
        // Always allow clipboard consumers time, including if this session is cancelled after posting.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { continuation.resume() }
        }
        return .attemptedPaste
    }

    @discardableResult
    func copyText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func targetIsValid(_ target: Target) -> Bool {
        guard hasAccessibilityPermission else { note("permission_missing", failure: true); return false }
        guard !IsSecureEventInputEnabled() else { note("secure_input", failure: true); return false }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier == target.processID, !isTerminal(application) else {
            note("application_changed", failure: true); return false
        }
        switch target.location {
        case .input(let element, let role, let originalRange):
            let focus = focusedElementResult(processID: target.processID)
            guard let current = focus.element else { note("focus_unavailable", error: focus.error, failure: true); return false }
            guard CFEqual(current, element) else { note("input_changed", failure: true); return false }
            guard editableRole(current) == role, let range = selectedRange(current) else { return false }
            guard range.location == originalRange.location && range.length == originalRange.length else {
                note("selection_changed", failure: true); return false
            }
            return true
        case .weChatWindow(let window, let interaction):
            guard interaction.isValid else { note("interaction_changed", failure: true); return false }
            guard application.bundleIdentifier == "com.tencent.xinWeChat",
                  let current = focusedWindow(processID: target.processID), CFEqual(current, window) else {
                note("window_changed", failure: true); return false
            }
            let focus = focusedElementResult(processID: target.processID)
            guard focus.element == nil && (focus.error == .noValue || focus.error == .attributeUnsupported) else {
                note("input_changed", error: focus.error, failure: true); return false
            }
            return true
        case .chatGPTWindow(let windowID, let interaction):
            guard interaction.isValid else { note("interaction_changed", failure: true); return false }
            guard let window = visibleWindow(processID: target.processID), window.id == windowID else {
                note("window_changed", failure: true); return false
            }
            let focus = focusedElementResult(processID: target.processID)
            guard Self.allowsChatGPTWindowCompatibility(applicationID: application.bundleIdentifier,
                hasFocusedElement: focus.element != nil, error: focus.error) else {
                note("input_changed", error: focus.error, failure: true); return false
            }
            return true
        }
    }

    static func allowsChatGPTWindowCompatibility(applicationID: String?, hasFocusedElement: Bool, error: AXError) -> Bool {
        applicationID == "com.openai.codex" && !hasFocusedElement && (error == .noValue || error == .attributeUnsupported)
    }

    private func visibleWindow(processID: pid_t) -> (id: CGWindowID, center: CGPoint)? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return Self.visibleWindow(processID: processID, windows: windows as? [[String: Any]] ?? [])
    }

    // Window Server order is front to back. Ignore other apps, floating panels and
    // invisible/empty windows; retain just the foremost normal window's identity.
    static func visibleWindow(processID: pid_t, windows: [[String: Any]]) -> (id: CGWindowID, center: CGPoint)? {
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == processID,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID, id != kCGNullWindowID,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary), bounds.width > 0, bounds.height > 0 else { continue }
            return (id, CGPoint(x: bounds.midX, y: bounds.midY))
        }
        return nil
    }

    private func focusedElementResult(processID: pid_t) -> (element: AXUIElement?, error: AXError) {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, error) }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        return (element, error)
    }

    private func focusedWindow(processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.25)
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
              subrole as? String == kAXStandardWindowSubrole else { return nil }
        return window
    }

    // Position metadata only. Screen choice follows the input field at session start.
    private func screenID(for element: AXUIElement) -> CGDirectDisplayID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let position = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(position) == .cgPoint, AXValueGetValue(position, .cgPoint, &point) else { return nil }
        return screenID(for: point)
    }

    private func screenID(for point: CGPoint) -> CGDirectDisplayID? {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }

    // This is cursor/selection metadata, never the text or value of the input.
    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            note("selection_unavailable", error: error, failure: true); return nil
        }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { note("selection_unavailable", failure: true); return nil }
        return range
    }

    private func editableRole(_ element: AXUIElement) -> String? {
        func attribute(_ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        var enabled: CFTypeRef?
        let enabledError = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        var roleValue: CFTypeRef?
        let roleError = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String
        guard let role, [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            let metadataRoles = [kAXGroupRole, "AXWebArea", kAXStaticTextRole, kAXButtonRole, kAXWindowRole, kAXApplicationRole]
            note("role_unsupported", error: roleError, role: metadataRoles.contains(role ?? "") ? role : "other", failure: true)
            return nil
        }
        guard Self.allowsEditing(enabled: enabled as? Bool, error: enabledError) else {
            note("input_disabled", error: enabledError, role: role, failure: true); return nil
        }
        let subrole = attribute(kAXSubroleAttribute) as? String
        let description = (attribute(kAXRoleDescriptionAttribute) as? String ?? "").lowercased()
        var canSetValue = DarwinBoolean(false)
        guard subrole != kAXSecureTextFieldSubrole,
              !description.contains("terminal"), !description.contains("终端") else {
            note("secure_field", role: role, failure: true); return nil
        }
        let error = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &canSetValue)
        guard error == .success, canSetValue.boolValue else {
            note("value_not_writable", error: error, role: role, failure: true); return nil
        }
        return role
    }

    static func allowsEditing(enabled: Bool?, error: AXError) -> Bool {
        // NSTextView omits AXEnabled. editableRole still requires writable AXValue.
        error == .attributeUnsupported || (error == .success && enabled == true)
    }

    private func isTerminal(_ application: NSRunningApplication) -> Bool {
        let identifiers = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm"]
        return identifiers.contains(application.bundleIdentifier ?? "")
    }

    isolated deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
}

// A session-scoped compatibility guard; ordinary key contents are never read or retained.
@MainActor final class InputInteractionGuard {
    private let processID: pid_t
    private let shortcut: (keyCode: UInt32, modifiers: UInt32)
    private var shortcutHeld = true // The triggering down precedes capture/start.
    private(set) var isValid = true
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private static let watched: [CGEventType] = [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown,
        .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]

    init(processID: pid_t, shortcut: (keyCode: UInt32, modifiers: UInt32)) {
        self.processID = processID
        self.shortcut = shortcut
    }

    func start() -> Bool {
        guard isValid else { return false }
        if eventTap != nil { return true }
        let mask = Self.watched.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    MainActor.assumeIsolated {
                        Unmanaged<InputInteractionGuard>.fromOpaque(context).takeUnretainedValue().process(type, event)
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { stop(); return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); stop(); return false
        }
        eventTap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.applicationActivated(app.processIdentifier) }
            })
        observers.append(center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { if self?.processID == app.processIdentifier { self?.isValid = false } }
            })
        return true
    }

    // Internal entry points let checks drive metadata without installing a live event tap.
    func process(_ type: CGEventType, _ event: CGEvent) {
        guard isValid else { return }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { isValid = false; return }
        guard Self.watched.contains(type) else { return } // Fn/modifier flagsChanged is not observed.
        if type == .keyDown || type == .keyUp {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            // A tapped Fn can also emit the system Globe key (179).
            if code == 179 { isValid = shortcut.keyCode == 63; return }
            if shortcut.keyCode != 63, code == Int64(shortcut.keyCode) {
                if type == .keyUp, shortcutHeld { shortcutHeld = false; return }
                var modifiers: UInt32 = 0
                if event.flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
                if event.flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
                if event.flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
                if event.flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
                if type == .keyDown, modifiers == shortcut.modifiers { shortcutHeld = true; return }
            }
        }
        isValid = false
    }

    func applicationActivated(_ pid: pid_t) {
        if pid != processID { isValid = false }
    }

    func stop() {
        isValid = false; shortcutHeld = false
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; source = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    isolated deinit { stop() }
}
