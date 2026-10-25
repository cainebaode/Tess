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
      (.record, []), (.custom1, .maskShift), (.custom2, .maskAlternate)
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
    precondition(triggers == [.init(action: .custom1, pressed: true, time: 10), .init(action: .custom1, pressed: false, time: 10.1)])
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
    _ = monitor.process(.flagsChanged, event(63, [.maskSecondaryFn, .maskAlternate], at: 30))
    monitor.commitPendingPress()
    _ = monitor.process(.tapDisabledByTimeout, event(63, [], at: 30.2))
    _ = monitor.process(.flagsChanged, event(63, [], at: 31))
    precondition(triggers == [.init(action: .custom2, pressed: true, time: 30), .init(action: .custom2, pressed: nil, time: 30.2)])
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
    precondition(ShortcutAction.voiceActions.count == 3)
    precondition(ShortcutAction.record.recordMode == .raw)
    precondition(ShortcutAction.custom1.recordMode == .custom1)
    precondition(ShortcutAction.custom2.recordMode == .custom2)
    precondition(TextMode.allCases == [.raw, .custom1, .custom2])

    var old = AppPreferences()
    old.bindings = [.record: .legacyRecord, .recordLight: ShortcutAction.custom1.defaults,
                    .recordList: ShortcutAction.recordList.defaults, .recordPolish: ShortcutAction.custom2.defaults,
                    .screenshot: ShortcutBinding(keyCode: 0, modifiers: UInt32(cmdKey | shiftKey))]
    old.shortcutVersion = 2
    old.textMode = .list
    old.alwaysPreview = true
    old.textPrompts = TextPrompts(common: "已有的通用规则", light: "已有轻量规则", list: "已有列表规则", polish: "已有润色规则")
    var migrated = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(old))
    migrated.migrate()
    precondition(migrated.alwaysPreview && migrated.shortcutVersion == 3)
    precondition(migrated.bindings[.record] == .fn && migrated.bindings[.result] == nil)
    precondition(migrated.bindings[.screenshot] == old.bindings[.screenshot])
    precondition(migrated.bindings[.custom1] == old.bindings[.recordLight])
    precondition(migrated.bindings[.custom2] == old.bindings[.recordPolish])
    precondition([ShortcutAction.recordLight, .recordList, .recordPolish].allSatisfy { migrated.bindings[$0] == nil })
    precondition(migrated.textMode == .custom2 && migrated.prompt(for: .custom2)?.id == "list")
    for mode in [TextMode.light, .list, .polish] {
      precondition(migrated.availablePrompts.first { $0.id == mode.rawValue }?.instructions == old.textPrompts?.systemPrompt(for: mode))
    }
    migrated.bindings[.custom1] = nil
    migrated.custom2PromptID = "digest"
    migrated.migrate()
    precondition(migrated.alwaysPreview && migrated.bindings[.custom1] == nil && migrated.custom2PromptID == "digest")

    var fresh = AppPreferences()
    fresh.migrate()
    precondition(fresh.bindings.count == 5 && fresh.bindings[.record] == .fn)
    precondition(fresh.prompt(for: .custom1)?.id == "cleanup" && fresh.prompt(for: .custom2)?.id == "agent")
    precondition(fresh.availablePrompts == TextPrompt.defaults)

    var build30 = AppPreferences()
    build30.shortcutVersion = 3
    build30.promptLibrary = TextPrompt.legacyDefaults
    build30.custom1PromptID = "light"
    build30.custom2PromptID = "instruction"
    build30.bindings[.custom1] = nil
    let priorBindings = build30.bindings
    build30.migrate()
    precondition(build30.availablePrompts == TextPrompt.defaults && build30.promptCatalogVersion == 1)
    precondition(build30.prompt(for: .custom1)?.id == "cleanup" && build30.prompt(for: .custom2)?.id == "agent")
    precondition(build30.bindings == priorBindings, "Catalog upgrades must not reset shortcuts")

    var edited = AppPreferences()
    edited.shortcutVersion = 3
    edited.promptLibrary = TextPrompt.legacyDefaults
    edited.promptLibrary![0].instructions = "用户自己写的规则"
    edited.promptLibrary![2].name = "简单润色"
    edited.custom2PromptID = "light"
    let userPolish = edited.promptLibrary![0]
    let userLight = edited.promptLibrary![2]
    edited = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(edited))
    edited.migrate()
    precondition(edited.prompt(for: .custom1) == userPolish, "Preserve implicit bindings to customized old defaults")
    precondition(edited.prompt(for: .custom2) == userLight, "Renaming a preset is a user edit")
    precondition(TextPrompt.defaults.allSatisfy { edited.availablePrompts.contains($0) })
    edited.promptLibrary?.removeAll { $0.id == "digest" }
    let once = edited.availablePrompts
    edited.migrate()
    precondition(edited.availablePrompts == once, "Do not re-add deleted templates on every launch")

    var legacyUnedited = AppPreferences()
    legacyUnedited.shortcutVersion = 2
    legacyUnedited.textPrompts = TextPrompts()
    legacyUnedited.textMode = .light
    legacyUnedited.migrate()
    precondition(legacyUnedited.availablePrompts == TextPrompt.defaults)
    precondition(legacyUnedited.prompt(for: .custom1)?.id == "cleanup")
    var conflicting = old
    conflicting.bindings[.recordLight] = .fn
    conflicting.migrate()
    precondition(conflicting.bindings[.record] == .fn && conflicting.bindings[.custom1] == nil)

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
    print("Input checks passed: three voice shortcuts, paired gestures, migration, automatic copy and cancellation. No live keyboard, microphone, network or user clipboard used.")
  }
}
