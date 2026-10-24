import AppKit
@preconcurrency import ApplicationServices
import Carbon

@MainActor
final class DeliveryService {
    struct Target {
        let processID: pid_t
        let applicationName: String
        let screenID: CGDirectDisplayID?
        fileprivate enum Location {
            case input(AXUIElement, role: String, range: CFRange)
            case weChatWindow(AXUIElement, WeChatInteractionGuard)
        }
        fileprivate let location: Location

        @MainActor func stopTracking() {
            if case .weChatWindow(_, let interaction) = location { interaction.stop() }
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

    private let pasteboard: NSPasteboard
    private var pasteInProgress = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // Called only when the user starts a recording or explicitly selects an input target.
    func captureTarget(compatibilityShortcut: (keyCode: UInt32, modifiers: UInt32)? = nil) -> Target? {
        guard hasAccessibilityPermission, !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !isTerminal(app) else { return nil }
        let focus = focusedElementResult(processID: app.processIdentifier)
        if let element = focus.element {
            guard let role = editableRole(element), let range = selectedRange(element) else { return nil }
            return Target(processID: app.processIdentifier, applicationName: app.localizedName ?? "",
                          screenID: screenID(for: element), location: .input(element, role: role, range: range))
        }
        // WeChat 4.1 exposes its window but no input element. This explicit compatibility
        // target cannot verify input type or selection; never use it for other applications
        // or when an accessible input was found but failed the normal checks.
        guard let compatibilityShortcut, app.bundleIdentifier == "com.tencent.xinWeChat",
              focus.error == .noValue || focus.error == .attributeUnsupported,
              let window = focusedWindow(processID: app.processIdentifier) else { return nil }
        let interaction = WeChatInteractionGuard(processID: app.processIdentifier, shortcut: compatibilityShortcut)
        guard interaction.start() else { return nil }
        return Target(processID: app.processIdentifier, applicationName: app.localizedName ?? "",
                      screenID: screenID(for: window), location: .weChatWindow(window, interaction))
    }

    func deliverVoice(text: String, target: Target?) async -> Outcome {
        guard !text.isEmpty else { return .unavailable("没有可插入的文字。") }
        guard !Task.isCancelled else { return .unavailable("已取消输入。") }
        guard let target, targetIsValid(target) else {
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
        guard hasAccessibilityPermission, !IsSecureEventInputEnabled(),
              let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier == target.processID, !isTerminal(application) else { return false }
        switch target.location {
        case .input(let element, let role, let originalRange):
            guard let current = focusedElementResult(processID: target.processID).element,
                  CFEqual(current, element), editableRole(current) == role,
                  let range = selectedRange(current) else { return false }
            return range.location == originalRange.location && range.length == originalRange.length
        case .weChatWindow(let window, let interaction):
            guard application.bundleIdentifier == "com.tencent.xinWeChat", interaction.isValid,
                  let current = focusedWindow(processID: target.processID), CFEqual(current, window) else { return false }
            let focus = focusedElementResult(processID: target.processID)
            return focus.element == nil && (focus.error == .noValue || focus.error == .attributeUnsupported)
        }
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
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }

    // This is cursor/selection metadata, never the text or value of the input.
    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    private func editableRole(_ element: AXUIElement) -> String? {
        func attribute(_ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        var enabled: CFTypeRef?
        let enabledError = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        guard let role = attribute(kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              Self.allowsEditing(enabled: enabled as? Bool, error: enabledError) else { return nil }
        let subrole = attribute(kAXSubroleAttribute) as? String
        let description = (attribute(kAXRoleDescriptionAttribute) as? String ?? "").lowercased()
        var canSetValue = DarwinBoolean(false)
        guard subrole != kAXSecureTextFieldSubrole,
              !description.contains("terminal"), !description.contains("终端"),
              AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &canSetValue) == .success,
              canSetValue.boolValue else { return nil }
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
}

// A session-scoped compatibility guard; ordinary key contents are never read or retained.
@MainActor final class WeChatInteractionGuard {
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
                        Unmanaged<WeChatInteractionGuard>.fromOpaque(context).takeUnretainedValue().process(type, event)
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
