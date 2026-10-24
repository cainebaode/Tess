import AppKit
import Carbon

@main @MainActor struct DeliveryCheck {
    static func checkWeChatInteractionGuard() {
        func event(_ code: UInt16 = 0, _ flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            return event
        }
        func fnGuard() -> WeChatInteractionGuard {
            WeChatInteractionGuard(processID: 123, shortcut: (63, 0))
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
                let guardState = WeChatInteractionGuard(processID: 123, shortcut: (keyCode, modifiers))
                guardState.process(type, event(179, [.maskControl, .maskAlternate]))
                precondition(!guardState.isValid, "Globe events are exempt only during an Fn recording")
            }
        }
        let custom = WeChatInteractionGuard(processID: 123, shortcut: (49, modifiers))
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
            let guardState = WeChatInteractionGuard(processID: 123, shortcut: (49, modifiers))
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
        stopped.stop(); stopped.stop()
        stopped.applicationActivated(123)
        stopped.process(.flagsChanged, event(63))
        precondition(!stopped.isValid && !stopped.start(), "A closed session cannot be rearmed")
        weak var released: WeChatInteractionGuard?
        do {
            let guardState = fnGuard()
            released = guardState
            guardState.stop()
        }
        precondition(released == nil)
    }

    static func main() async {
        checkWeChatInteractionGuard()
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
        print("Delivery checks passed: WeChat interaction invalidation, Fn-only Globe event exemption and custom shortcut protections, single attempt, multi-type restoration, concurrent copy, target change, cancellation, rapid reentry, oversized clipboard protection and unavailable-target recovery. Synthetic event metadata, isolated pasteboard and local callbacks only; no live event tap, target, keyboard, microphone or user clipboard used.")
    }
}
