import AppKit
import Carbon

// Only the unrelated text-mode value is supplied; the shortcut service is production code.
enum TextMode { case raw, custom1, custom2 }

@main @MainActor struct HotkeyCheck {
  struct Trigger: Equatable {
    let action: ShortcutAction
    let pressed: Bool?
  }

  static func event(_ code: Int64, _ flags: CGEventFlags, at time: TimeInterval,
                    type: CGEventType = .flagsChanged, isRepeat: Bool = false) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: type != .keyUp)!
    event.type = type
    event.flags = flags
    event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
    event.timestamp = UInt64(time * 1_000_000_000)
    return event
  }

  static func main() async throws {
    // These would take ordinary editing commands away from every target application.
    for code: UInt32 in [0, 1, 3, 6, 7, 8, 9, 17, 31, 35, 45] {
      precondition(ShortcutBinding(keyCode: code, modifiers: UInt32(cmdKey)).validationError != nil)
    }
    precondition(ShortcutBinding(keyCode: 6, modifiers: UInt32(cmdKey | shiftKey)).validationError != nil)
    precondition(ShortcutBinding(keyCode: 9, modifiers: UInt32(cmdKey | optionKey | shiftKey)).validationError != nil)
    for binding in [ShortcutAction.screenshot.defaults, ShortcutAction.result.defaults, ShortcutBinding.legacyRecord] {
      precondition(binding.validationError == nil)
    }
    for binding in [ShortcutBinding(keyCode: 0, modifiers: 0),
                    ShortcutBinding(keyCode: 53, modifiers: UInt32(optionKey)),
                    ShortcutBinding(keyCode: 49, modifiers: UInt32(cmdKey)),
                    ShortcutBinding(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey))] {
      precondition(binding.validationError != nil)
    }

    let bindings = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
      action.defaults.isFn ? (action, action.defaults) : nil
    })
    var triggers: [Trigger] = []
    let monitor = FnKeyMonitor(bindings: bindings) { action, pressed, _ in
      triggers.append(Trigger(action: action, pressed: pressed))
    }
    // Losing the monitor while Fn is held must interrupt the session exactly once.
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 1))
    monitor.commitPendingPress()
    monitor.stop()
    monitor.stop()
    _ = monitor.process(.flagsChanged, event(63, [], at: 2))
    precondition(triggers == [.init(action: .record, pressed: true), .init(action: .record, pressed: nil)],
                 "Stopping a held Fn monitor must cancel its session, without a late release")

    // A release can be lost during sleep. Resetting the monitor must allow the first new press.
    triggers = []
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 2.1))
    monitor.commitPendingPress()
    monitor.stop()
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 2.5))
    monitor.commitPendingPress()
    precondition(triggers == [.init(action: .record, pressed: true), .init(action: .record, pressed: nil),
                              .init(action: .record, pressed: true)],
                 "The first Fn press after interruption must start even if the previous release was lost")
    monitor.stop()

    // A pending press must not start recording after the monitor has stopped.
    triggers = []
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 3))
    monitor.stop()
    try await Task.sleep(for: .milliseconds(120))
    precondition(triggers.isEmpty)

    // The next gesture starts normally, and adjacent modifiers select one mode only.
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 4))
    _ = monitor.process(.flagsChanged, event(56, [.maskSecondaryFn, .maskShift], at: 4.04))
    _ = monitor.process(.flagsChanged, event(56, .maskSecondaryFn, at: 4.06))
    _ = monitor.process(.flagsChanged, event(63, [], at: 4.1))
    precondition(triggers == [.init(action: .custom1, pressed: true), .init(action: .custom1, pressed: false)])

    for action in ShortcutAction.voiceActions {
      triggers = []
      let binding = bindings[action]!
      var flags = CGEventFlags.maskSecondaryFn
      if binding.modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
      if binding.modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
      if binding.modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
      _ = monitor.process(.flagsChanged, event(63, flags, at: 5))
      monitor.commitPendingPress()
      _ = monitor.process(.flagsChanged, event(63, flags, at: 5.1))
      _ = monitor.process(.flagsChanged, event(63, [], at: 6))
      _ = monitor.process(.flagsChanged, event(63, [], at: 6.1))
      precondition(triggers == [.init(action: action, pressed: true), .init(action: action, pressed: false)])
    }

    // Signed codes denote down/up; cover every interleaving of the two ordered pairs.
    let globeOrders: [[Int64]] = [
      [179, -179, 63, -63], [179, 63, -179, -63], [179, 63, -63, -179],
      [63, -63, 179, -179], [63, 179, -63, -179], [63, 179, -179, -63]
    ]
    for order in globeOrders {
      triggers = []
      for (index, signedCode) in order.enumerated() {
        let code = abs(signedCode)
        let down = signedCode > 0
        let type: CGEventType = code == 63 ? .flagsChanged : down ? .keyDown : .keyUp
        let flags: CGEventFlags = code == 63 && down ? .maskSecondaryFn : []
        let before = triggers
        precondition(monitor.process(type, event(code, flags, at: 10 + Double(index) / 100, type: type)) == nil,
                     "A bound Fn must consume both event pairs in either order")
        if code == 179 { precondition(triggers == before, "Globe events must never trigger recording") }
        if code == 63, down { monitor.commitPendingPress() }
      }
      precondition(triggers == [.init(action: .record, pressed: true), .init(action: .record, pressed: false)])
    }

    // Unbound Cmd+Fn stays with the system, including when Cmd is released before Globe up.
    for order in globeOrders {
      triggers = []
      for (index, signedCode) in order.enumerated() {
        let code = abs(signedCode)
        let down = signedCode > 0
        let type: CGEventType = code == 63 ? .flagsChanged : down ? .keyDown : .keyUp
        let flags: CGEventFlags = down ? (code == 63 ? [.maskSecondaryFn, .maskCommand] : .maskCommand) : []
        precondition(monitor.process(type, event(code, flags, at: 11 + Double(index) / 100, type: type)) != nil,
                     "An unbound Fn chord must preserve both system event pairs")
        if code == 63, down { monitor.commitPendingPress() }
      }
      precondition(triggers.isEmpty)
    }

    // Globe keeps its down decision through repeats and modifier changes; other keys pass.
    triggers = []
    precondition(monitor.process(.keyDown, event(179, .maskShift, at: 12, type: .keyDown)) == nil)
    precondition(monitor.process(.keyDown, event(179, .maskCommand, at: 12.1, type: .keyDown, isRepeat: true)) == nil)
    for type in [CGEventType.keyDown, .keyUp] {
      precondition(monitor.process(type, event(0, .maskSecondaryFn, at: 12.2, type: type)) != nil,
                   "Ordinary keys must pass even during a captured Globe pair")
    }
    precondition(monitor.process(.keyUp, event(179, [], at: 12.3, type: .keyUp)) == nil)
    precondition(triggers.isEmpty)
    precondition(monitor.process(.keyDown, event(179, .maskCommand, at: 12.4, type: .keyDown)) != nil)
    precondition(monitor.process(.keyDown, event(179, [], at: 12.5, type: .keyDown, isRepeat: true)) != nil)
    precondition(monitor.process(.keyUp, event(179, [], at: 12.6, type: .keyUp)) != nil)

    // An orphan repeat/up cannot acquire a capture; a fresh down replaces a lost old pair.
    precondition(monitor.process(.keyDown, event(179, [], at: 13, type: .keyDown, isRepeat: true)) != nil)
    precondition(monitor.process(.keyUp, event(179, [], at: 13.1, type: .keyUp)) != nil)
    precondition(monitor.process(.keyDown, event(179, [], at: 13.2, type: .keyDown)) == nil)
    precondition(monitor.process(.keyDown, event(179, .maskCommand, at: 13.3, type: .keyDown)) != nil)
    precondition(monitor.process(.keyUp, event(179, [], at: 13.4, type: .keyUp)) != nil)

    // No Globe may be emitted for a long Fn hold. It must not affect the next unbound chord.
    _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 14))
    monitor.commitPendingPress()
    _ = monitor.process(.flagsChanged, event(63, [], at: 20))
    triggers = []
    precondition(monitor.process(.keyDown, event(179, .maskCommand, at: 20.01, type: .keyDown)) != nil)
    precondition(monitor.process(.flagsChanged, event(63, [.maskSecondaryFn, .maskCommand], at: 20.02)) != nil)
    monitor.commitPendingPress()
    precondition(monitor.process(.flagsChanged, event(63, [], at: 20.03)) != nil)
    precondition(monitor.process(.keyUp, event(179, [], at: 20.04, type: .keyUp)) != nil)
    precondition(triggers.isEmpty)

    // Binding only Shift+Fn does not claim bare Globe, even after a captured pair.
    let shiftMonitor = FnKeyMonitor(bindings: [.custom1: ShortcutAction.custom1.defaults]) { _, _, _ in
      preconditionFailure("Globe alone cannot trigger a shortcut")
    }
    precondition(shiftMonitor.process(.keyDown, event(179, .maskShift, at: 21, type: .keyDown)) == nil)
    precondition(shiftMonitor.process(.keyUp, event(179, [], at: 21.1, type: .keyUp)) == nil)
    precondition(shiftMonitor.process(.keyDown, event(179, [], at: 21.2, type: .keyDown)) != nil)
    precondition(shiftMonitor.process(.keyUp, event(179, [], at: 21.3, type: .keyUp)) != nil)

    // Stop and both tap-disable paths discard a pending Globe pair and any Fn gesture.
    for interruption in [CGEventType?.none, .tapDisabledByTimeout, .tapDisabledByUserInput] {
      triggers = []
      precondition(monitor.process(.keyDown, event(179, [], at: 22, type: .keyDown)) == nil)
      _ = monitor.process(.flagsChanged, event(63, .maskSecondaryFn, at: 22.01))
      monitor.commitPendingPress()
      if let interruption { _ = monitor.process(interruption, event(0, [], at: 22.02)) }
      else { monitor.stop() }
      precondition(triggers == [.init(action: .record, pressed: true), .init(action: .record, pressed: nil)])
      precondition(monitor.process(.keyUp, event(179, [], at: 22.03, type: .keyUp)) != nil)
      precondition(monitor.process(.keyDown, event(179, [], at: 22.04, type: .keyDown, isRepeat: true)) != nil)
      _ = monitor.process(.flagsChanged, event(63, [], at: 22.05))
      precondition(triggers.count == 2)
    }

    var gesture = RecordKeyGesture()
    precondition(gesture.press(at: 1, phase: .idle, automatic: true, hold: true) == .start)
    precondition(gesture.release(at: 1.1, phase: .loading, automatic: true, hold: true) == .none)
    precondition(gesture.press(at: 2, phase: .loading, automatic: true, hold: true) == .cancel)
    precondition(gesture.press(at: 3, phase: .idle, automatic: true, hold: true) == .start)
    precondition(gesture.release(at: 4, phase: .recording, automatic: true, hold: true) == .stop)
    print("Hotkey checks passed: reserved editing shortcuts, interrupted Fn, first press after a lost release, pending cancellation, three voice shortcuts, Globe pair ordering, unbound/ordinary keys, repeat and interruption cleanup, and gesture recovery. Synthetic events only; no live keyboard, event tap, microphone or UI used.")
  }
}
