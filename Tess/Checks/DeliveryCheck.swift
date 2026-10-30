import AppKit
import Carbon

@main @MainActor struct DeliveryCheck {
    static func checkCompatibilityInteractionGuard() {
        func event(_ code: UInt16 = 0, _ flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            return event
        }
        func fnGuard() -> InputInteractionGuard {
            InputInteractionGuard(processID: 123, shortcut: (63, 0))
        }
        let fn = fnGuard()
        for _ in 0..<2 {
            fn.process(.flagsChanged, event(63, .maskSecondaryFn))
            fn.process(.flagsChanged, event(63))
            fn.process(.keyDown, event(179))
            fn.process(.keyUp, event(179))
        }
        precondition(fn.isValid, "Fn tap/hold edges and their system Globe events must not invalidate the target")
        fn.applicationActivated(123)
        precondition(fn.isValid)
        fn.applicationActivated(456)
        fn.applicationActivated(123)
        fn.process(.keyDown, event(179))
        precondition(!fn.isValid, "Leaving and returning must not revive the original target")

        let modifiers = UInt32(controlKey | optionKey)
        for keyCode: UInt32 in [49, 179] {
            for type: CGEventType in [.keyDown, .keyUp] {
                let guardState = InputInteractionGuard(processID: 123, shortcut: (keyCode, modifiers))
                guardState.process(type, event(179, [.maskControl, .maskAlternate]))
                precondition(!guardState.isValid, "Globe events are exempt only during an Fn recording")
            }
        }
        let custom = InputInteractionGuard(processID: 123, shortcut: (49, modifiers))
        // Start happened before monitoring. Modifiers may be released before the principal key.
        custom.process(.flagsChanged, event(58))
        custom.process(.keyUp, event(49))
        precondition(custom.isValid)
        custom.process(.keyDown, event(49, [.maskControl, .maskAlternate]))
        custom.process(.keyDown, event(49, [.maskControl, .maskAlternate]))
        custom.process(.flagsChanged, event(59))
        custom.process(.keyUp, event(49))
        precondition(custom.isValid, "The exact custom stop chord and its release must remain usable")
        custom.process(.keyDown, event(49))
        precondition(!custom.isValid, "The same key without its shortcut modifiers is ordinary input")
        for (code, flags) in [(UInt16(0), CGEventFlags([.maskControl, .maskAlternate])),
                               (UInt16(49), CGEventFlags([.maskControl, .maskAlternate, .maskShift]))] {
            let guardState = InputInteractionGuard(processID: 123, shortcut: (49, modifiers))
            guardState.process(.keyDown, event(code, flags))
            precondition(!guardState.isValid, "Only the exact configured chord is exempt")
        }
        for type: CGEventType in [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                 .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
                                 .tapDisabledByTimeout, .tapDisabledByUserInput] {
            let guardState = fnGuard()
            guardState.process(type, event())
            precondition(!guardState.isValid, "User interaction and lost monitoring must invalidate")
        }
        let stopped = fnGuard()
        InputInteractionGuard.hudWindowNumber = 321
        for type: CGEventType in [.leftMouseDown, .scrollWheel, .leftMouseDragged] {
            let hud = fnGuard()
            let pointer = CGEvent(source: nil)!
            pointer.type = type
            hud.process(type, pointer, windowAtPointer: 321)
            precondition(hud.isValid, "Nonactivating HUD interaction must keep the original target")
            hud.process(type, pointer, windowAtPointer: 322)
            precondition(!hud.isValid, "Another window still invalidates the target")
        }
        let hudKey = fnGuard()
        let typed = event()
        hudKey.process(.keyDown, typed, windowAtPointer: 321)
        precondition(!hudKey.isValid, "Pointing at the HUD must not exempt typing")
        InputInteractionGuard.hudWindowNumber = nil
        stopped.stop(); stopped.stop()
        stopped.applicationActivated(123)
        stopped.process(.flagsChanged, event(63))
        precondition(!stopped.isValid && !stopped.start(), "A closed session cannot be rearmed")
        weak var released: InputInteractionGuard?
        do {
            let guardState = fnGuard()
            released = guardState
            guardState.stop()
        }
        precondition(released == nil)
    }

    static func main() async {
        checkCompatibilityInteractionGuard()
        // Reproduce the user's AX noValue without querying a real application.
        for error in [AXError.noValue, .attributeUnsupported] {
            precondition(DeliveryService.allowsChatGPTWindowCompatibility(applicationID: "com.openai.codex",
                hasFocusedElement: false, error: error))
        }
        for error in [AXError.success, .cannotComplete, .apiDisabled, .notImplemented, .invalidUIElement] {
            precondition(!DeliveryService.allowsChatGPTWindowCompatibility(applicationID: "com.openai.codex",
                hasFocusedElement: false, error: error))
        }
        for applicationID in [nil, "com.openai.chat", "com.google.Chrome", "com.tencent.xinWeChat"] {
            precondition(!DeliveryService.allowsChatGPTWindowCompatibility(applicationID: applicationID,
                hasFocusedElement: false, error: .noValue))
        }
        precondition(!DeliveryService.allowsChatGPTWindowCompatibility(applicationID: "com.openai.codex",
            hasFocusedElement: true, error: .noValue), "A present input that fails normal validation must never use the window fallback")
        func window(_ id: UInt32, pid: Int32 = 123, layer: Int = 0, alpha: Double = 1, bounds: CGRect = CGRect(x: 100, y: 200, width: 600, height: 400)) -> [String: Any] {
            [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowLayer as String: NSNumber(value: layer), kCGWindowAlpha as String: NSNumber(value: alpha),
             kCGWindowBounds as String: bounds.dictionaryRepresentation]
        }
        let selectedWindow = DeliveryService.visibleWindow(processID: 123, windows: [
            window(1, pid: 456), window(2, layer: 3), window(3, alpha: 0), window(4, bounds: .zero), window(0), window(5), window(6)
        ])
        precondition(selectedWindow?.id == 5 && selectedWindow?.center == CGPoint(x: 400, y: 400))
        precondition(DeliveryService.visibleWindow(processID: 123, windows: [window(7), window(5)])?.id != selectedWindow?.id,
                     "Switching to another window in the same app must invalidate the recorded window")
        precondition(DeliveryService.visibleWindow(processID: 123, windows: [window(1, pid: 456)]) == nil)
        // Cold renderers need their own accessibility activation request. Chrome uses
        // EnhancedUserInterface; Electron's ManualAccessibility is not supported there.
        for applicationID in ["com.openai.codex", "com.openai.chat"] {
            var prepared = false
            let result = DeliveryService.prepareDesktopAccessibility(applicationID: applicationID) { attribute in
                precondition(attribute == "AXManualAccessibility")
                prepared = true
                return .success
            }
            precondition(prepared && result == .success)
            precondition(DeliveryService.prepareDesktopAccessibility(applicationID: applicationID,
                setAttribute: { _ in .attributeUnsupported }) == .attributeUnsupported)
        }
        var browserRequests: [String] = []
        let browserResult = DeliveryService.prepareDesktopAccessibility(applicationID: "com.google.Chrome") { attribute in
            browserRequests.append(attribute)
            return .success
        }
        precondition(browserRequests == ["AXEnhancedUserInterface"] && browserResult == .success,
                     "Chrome must activate web accessibility before capturing a focused input")
        for error in [AXError.attributeUnsupported, .notImplemented, .cannotComplete, .apiDisabled] {
            precondition(DeliveryService.prepareDesktopAccessibility(applicationID: "com.google.Chrome",
                setAttribute: { _ in error }) == error, "Activation must preserve the actual AX result")
        }
        for applicationID in [nil, "com.google.Chrome.fake", "com.apple.Safari", "com.apple.TextEdit", "com.tencent.xinWeChat"] {
            precondition(DeliveryService.prepareDesktopAccessibility(applicationID: applicationID,
                setAttribute: { _ in preconditionFailure("Other applications must keep their existing AX behavior") }) == nil)
        }
        // TextEdit's editable NSTextView omits AXEnabled; explicit disabled/error states still reject.
        precondition(DeliveryService.allowsEditing(enabled: nil, error: .attributeUnsupported))
        precondition(DeliveryService.allowsEditing(enabled: true, error: .success))
        precondition(!DeliveryService.allowsEditing(enabled: false, error: .success))
        precondition(!DeliveryService.allowsEditing(enabled: nil, error: .success))
        precondition(!DeliveryService.allowsEditing(enabled: nil, error: .cannotComplete))
        precondition(!DeliveryService.allowsEditing(enabled: nil, error: .apiDisabled))
        // This pasteboard is independent of the user's clipboard. Posting is a local test callback.
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let delivery = DeliveryService(pasteboard: pasteboard)
        let customType = NSPasteboard.PasteboardType("life.tess.delivery-check")
        let original = NSPasteboardItem()
        precondition(original.setString("原有内容", forType: .string))
        precondition(original.setData(Data([0, 1, 2, 255]), forType: customType))
        precondition(pasteboard.writeObjects([original]))

        var posts = 0
        let inserted = await delivery.pasteUsingClipboard(text: "中文 English\n第二行", validateTarget: { true }) {
            posts += 1
            precondition(pasteboard.string(forType: .string) == "中文 English\n第二行")
        }
        guard case .attemptedPaste = inserted else { preconditionFailure("Expected one paste attempt") }
        precondition(posts == 1)
        precondition(pasteboard.string(forType: .string) == "原有内容")
        precondition(pasteboard.data(forType: customType) == Data([0, 1, 2, 255]))

        // A new copy made during the consumer window must survive restoration.
        _ = await delivery.pasteUsingClipboard(text: "转录结果", validateTarget: { true }) {
            posts += 1
            pasteboard.clearContents()
            precondition(pasteboard.setString("用户刚复制的内容", forType: .string))
        }
        precondition(posts == 2 && pasteboard.string(forType: .string) == "用户刚复制的内容")

        // Reject changed focus before touching the pasteboard or posting a key.
        var validations = 0
        let beforeInvalidTarget = pasteboard.changeCount
        let invalid = await delivery.pasteUsingClipboard(text: "不能输入", validateTarget: {
            validations += 1
            return validations == 1
        }) { preconditionFailure("Changed targets must not receive paste events") }
        guard case .unavailable = invalid else { preconditionFailure("Expected invalid-target failure") }
        precondition(pasteboard.changeCount == beforeInvalidTarget)
        precondition(pasteboard.string(forType: .string) == "用户刚复制的内容")

        // If focus changes after staging text, restore every previous clipboard type.
        validations = 0
        let changedAfterStaging = await delivery.pasteUsingClipboard(text: "不能输入", validateTarget: {
            validations += 1
            return validations < 3
        }) { preconditionFailure("Changed targets must not receive paste events") }
        guard case .unavailable = changedAfterStaging else { preconditionFailure("Expected staged-target failure") }
        precondition(pasteboard.string(forType: .string) == "用户刚复制的内容")

        // Cancellation before posting must leave the clipboard unchanged.
        let beforeCancel = pasteboard.changeCount
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await delivery.pasteUsingClipboard(text: "迟到结果", validateTarget: { true }) {
                preconditionFailure("Cancelled sessions must not post")
            }
        }
        guard case .unavailable = await cancelled.value else { preconditionFailure("Expected cancellation") }
        precondition(pasteboard.changeCount == beforeCancel)

        // A cancelled paste may still be consumed while the next session reaches delivery.
        // The second transaction must not snapshot and later restore the first transcript.
        pasteboard.clearContents()
        precondition(pasteboard.setString("连续输入前的剪贴板", forType: .string))
        let first = Task { @MainActor in
            await delivery.pasteUsingClipboard(text: "第一条", validateTarget: { true }) { posts += 1 }
        }
        try? await Task.sleep(for: .milliseconds(20))
        first.cancel()
        let waiting = Task { @MainActor in
            await delivery.pasteUsingClipboard(text: "取消的排队结果", validateTarget: { true }) {
                preconditionFailure("Cancellation while waiting must not post")
            }
        }
        await Task.yield()
        waiting.cancel()
        guard case .unavailable = await waiting.value else { preconditionFailure("Expected waiting cancellation") }
        let second = await delivery.pasteUsingClipboard(text: "第二条", validateTarget: { true }) { posts += 1 }
        guard case .attemptedPaste = await first.value, case .attemptedPaste = second else {
            preconditionFailure("Both already-authorized paste attempts should finish")
        }
        precondition(pasteboard.string(forType: .string) == "连续输入前的剪贴板",
                     "Overlapping transactions must not restore a stale transcript")
        precondition(posts == 4)

        // Oversized existing data must remain intact; the caller must surface recovery instead.
        pasteboard.clearContents()
        let largeData = Data(repeating: 7, count: 32 * 1_024 * 1_024 + 1)
        precondition(pasteboard.setData(largeData, forType: customType))
        let beforeLarge = pasteboard.changeCount
        let large = await delivery.pasteUsingClipboard(text: "不能覆盖", validateTarget: { true }) {
            preconditionFailure("Unrecoverable clipboard contents must not be replaced")
        }
        guard case .unavailable = large else { preconditionFailure("Expected clipboard protection") }
        precondition(pasteboard.changeCount == beforeLarge && pasteboard.data(forType: customType) == largeData)

        // The established recovery path for a target that was already unavailable remains explicit.
        let unavailableTarget = await delivery.deliverVoice(text: "可恢复的结果", target: nil)
        guard case .copiedToClipboard = unavailableTarget else { preconditionFailure("Expected recovery copy") }
        precondition(pasteboard.string(forType: .string) == "可恢复的结果")

        // Persistent diagnostics must stay bounded, survive restart and exclude text.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TessInputDiagnostics-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnosticURL = directory.appendingPathComponent("Diagnostics/input.json")
        let diagnosticDelivery = DeliveryService(pasteboard: pasteboard, diagnosticURL: diagnosticURL)
        let privateText = "private-transcript-must-not-appear-" + UUID().uuidString
        for _ in 0..<105 { _ = await diagnosticDelivery.deliverVoice(text: privateText, target: nil) }
        let diagnosticData = try! Data(contentsOf: diagnosticURL)
        let stored = try! JSONDecoder().decode([DeliveryService.DiagnosticEvent].self, from: diagnosticData)
        precondition(stored.count == 100 && stored.allSatisfy { $0.code == "copied_fallback" })
        precondition(!String(decoding: diagnosticData, as: UTF8.self).contains(privateText))
        precondition(!diagnosticDelivery.diagnosticReport.contains(privateText))
        let reloaded = DeliveryService(pasteboard: pasteboard, diagnosticURL: diagnosticURL)
        precondition(reloaded.diagnosticEvents.count == 100)
        let countBeforeCancellation = diagnosticDelivery.diagnosticReport
        let cancelledDiagnostic = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await diagnosticDelivery.deliverVoice(text: privateText, target: nil)
        }
        guard case .unavailable = await cancelledDiagnostic.value else { preconditionFailure("Cancellation must not write diagnostics or copy text") }
        precondition(diagnosticDelivery.diagnosticReport == countBeforeCancellation)
        print("Delivery checks passed: ChatGPT missing-focus window eligibility, application/error scope, front-window identity and filtering, shared WeChat/ChatGPT Fn interaction protections, AX preparation, bounded private-text-free diagnostics, clipboard restoration, target changes and cancellation. Synthetic window metadata, isolated callbacks and pasteboard only; no live window/AX queries, event tap, keyboard, microphone or user clipboard used.")
    }
}
