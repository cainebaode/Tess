import AppKit
import Carbon

@main @MainActor struct InputCheck {
  struct Trigger: Equatable {
    let action: ShortcutAction
    let pressed: Bool?
    let time: TimeInterval
  }

  static func event(_ keyCode: Int64, _ flags: CGEventFlags, at time: TimeInterval) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
    event.type = .flagsChanged
    event.flags = flags
    event.timestamp = UInt64(time * 1_000_000_000)
    return event
  }

  static func main() async throws {
    let bindings = AppPreferences().bindings.filter { $0.value.isFn }
    let combinations: [(ShortcutAction, CGEventFlags)] = [
      (.record, []), (.recordLight, .maskShift), (.recordList, .maskControl), (.recordPolish, .maskAlternate)
    ]
    for (action, modifiers) in combinations {
      var triggers: [Trigger] = []
      let monitor = FnKeyMonitor(bindings: bindings) { triggers.append(.init(action: $0, pressed: $1, time: $2)) }
      precondition(monitor.process(.flagsChanged, event(63, modifiers.union(.maskSecondaryFn), at: 1)) == nil)
      monitor.commitPendingPress()
      _ = monitor.process(.flagsChanged, event(63, modifiers.union(.maskSecondaryFn), at: 1.1))
      _ = monitor.process(.flagsChanged, event(56, .maskSecondaryFn, at: 1.2))
      precondition(monitor.process(.flagsChanged, event(63, [], at: 2)) == nil)
      _ = monitor.process(.flagsChanged, event(63, [], at: 2.1))
      precondition(triggers == [.init(action: action, pressed: true, time: 1), .init(action: action, pressed: false, time: 2)])
    }

    // Fn first, then a nearby modifier: one cleanup trigger, never a raw trigger.
    var triggers: [Trigger] = []
    let monitor = FnKeyMonitor(bindings: bindings) { triggers.append(.init(action: $0, pressed: $1, time: $2)) }
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 10))
    _ = monitor.process(.flagsChanged, event(56, [.maskSecondaryFn, .maskShift], at: 10.04))
    _ = monitor.process(.flagsChanged, event(56, .maskSecondaryFn, at: 10.06))
    _ = monitor.process(.flagsChanged, event(63, [], at: 10.1))
    precondition(triggers == [.init(action: .recordLight, pressed: true, time: 10), .init(action: .recordLight, pressed: false, time: 10.1)])
    try await Task.sleep(for: .milliseconds(100))
    precondition(triggers.count == 2)

    // Unbound modifiers and ordinary key events remain available to other apps.
    triggers = []
    precondition(monitor.process(.flagsChanged, event(63, [.maskSecondaryFn, .maskCommand], at: 20)) != nil)
    monitor.commitPendingPress()
    precondition(monitor.process(.keyDown, event(0, [], at: 20.1)) != nil)
    _ = monitor.process(.flagsChanged, event(63, [], at: 21))
    precondition(triggers.isEmpty)

    // Tap interruption cancels one held trigger; stopped pending callbacks cannot start it.
    _ = monitor.process(.flagsChanged, event(63, [.maskSecondaryFn, .maskControl], at: 30))
    monitor.commitPendingPress()
    _ = monitor.process(.tapDisabledByTimeout, event(63, [], at: 30.2))
    _ = monitor.process(.flagsChanged, event(63, [], at: 31))
    precondition(triggers == [.init(action: .recordList, pressed: true, time: 30), .init(action: .recordList, pressed: nil, time: 30.2)])
    triggers = []
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 40))
    monitor.stop()
    monitor.commitPendingPress()
    precondition(triggers.isEmpty)

    var gesture = RecordKeyGesture()
    precondition(gesture.press(at: 1, phase: .idle, automatic: true, hold: true) == .start)
    precondition(gesture.release(at: 1.1, phase: .loading, automatic: true, hold: true) == .none)
    precondition(gesture.press(at: 2, phase: .loading, automatic: true, hold: true) == .cancel)
    precondition(gesture.press(at: 3, phase: .idle, automatic: true, hold: true) == .start)
    precondition(gesture.release(at: 4, phase: .recording, automatic: true, hold: true) == .stop)
    precondition(gesture.press(at: 5, phase: .idle, automatic: false, hold: true) == .start)
    precondition(gesture.release(at: 6, phase: .loading, automatic: false, hold: true) == .cancel)
    for (action, _) in combinations { precondition(action.recordMode != nil) }
    precondition(ShortcutAction.record.recordMode == .raw)
    precondition(ShortcutAction.recordLight.recordMode == .light)
    precondition(ShortcutAction.recordList.recordMode == .list)
    precondition(ShortcutAction.recordPolish.recordMode == .polish)

    var old = AppPreferences()
    old.bindings = [.record: .legacyRecord, .screenshot: ShortcutAction.screenshot.defaults]
    old.bindings[.screenshot] = ShortcutBinding(keyCode: 0, modifiers: UInt32(cmdKey | shiftKey))
    old.shortcutVersion = nil
    old.alwaysPreview = true
    var migrated = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(old))
    migrated.migrate()
    precondition(!migrated.alwaysPreview)
    precondition(migrated.bindings[.record] == .fn && migrated.bindings[.result] == nil)
    precondition(migrated.bindings[.screenshot] == old.bindings[.screenshot])
    precondition(migrated.bindings[.recordLight] == ShortcutAction.recordLight.defaults)
    precondition(migrated.bindings[.recordList] == ShortcutAction.recordList.defaults)
    precondition(migrated.bindings[.recordPolish] == ShortcutAction.recordPolish.defaults)
    migrated.bindings[.recordLight] = nil
    migrated.alwaysPreview = true
    migrated.migrate()
    precondition(migrated.alwaysPreview)
    precondition(migrated.bindings[.recordLight] == nil)
    old.shortcutVersion = 1
    old.bindings[.record] = ShortcutAction.recordLight.defaults
    old.migrate()
    precondition(old.bindings[.record] == ShortcutAction.recordLight.defaults && old.bindings[.recordLight] == nil)
    old.shortcutVersion = 1; old.bindings[.record] = nil
    old.migrate()
    precondition(old.bindings[.record] == nil)

    // Use an isolated pasteboard: never read or write the user's clipboard.
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let delivery = DeliveryService(pasteboard: pasteboard)
    let outcome = await delivery.deliverVoice(text: "输入位置切换后的结果", target: nil)
    guard case .copiedToClipboard = outcome else { preconditionFailure("Unavailable targets must copy automatically") }
    precondition(pasteboard.string(forType: .string) == "输入位置切换后的结果")
    let count = pasteboard.changeCount
    let empty = await delivery.deliverVoice(text: "", target: nil)
    guard case .unavailable = empty else { preconditionFailure("Empty results must not be delivered") }
    let cancelled = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return await delivery.deliverVoice(text: "迟到结果", target: nil)
    }
    guard case .unavailable = await cancelled.value else { preconditionFailure("Cancelled sessions must not copy") }
    precondition(pasteboard.changeCount == count && pasteboard.string(forType: .string) == "输入位置切换后的结果")
    print("Input checks passed: four Fn modes, paired gestures, migration, automatic copy and cancellation. No live keyboard, microphone, network or user clipboard used.")
  }
}
