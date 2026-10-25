import AppKit
import ApplicationServices
import Carbon
import Observation

enum ShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
  case record, custom1, custom2, screenshot, result
  // Legacy keys are decoded for migration, never registered.
  case recordLight, recordList, recordPolish
  static let allCases: [ShortcutAction] = [.record, .custom1, .custom2, .screenshot, .result]
  static let voiceActions: [ShortcutAction] = [.record, .custom1, .custom2]
  var id: String { rawValue }
  var recordMode: TextMode? {
    switch self {
    case .record: .raw
    case .custom1: .custom1
    case .custom2: .custom2
    case .screenshot, .result, .recordLight, .recordList, .recordPolish: nil
    }
  }
  var defaults: ShortcutBinding {
    switch self {
    case .record: .fn
    case .custom1, .recordLight: ShortcutBinding(keyCode: 63, modifiers: UInt32(shiftKey))
    case .recordList: ShortcutBinding(keyCode: 63, modifiers: UInt32(controlKey))
    case .custom2, .recordPolish: ShortcutBinding(keyCode: 63, modifiers: UInt32(optionKey))
    case .screenshot, .result: ShortcutBinding(keyCode: self == .screenshot ? 1 : 15,
                                            modifiers: UInt32(controlKey | optionKey))
    }
  }
}

struct ShortcutBinding: Codable, Equatable, Sendable {
  var keyCode: UInt32
  var modifiers: UInt32
  static let fn = ShortcutBinding(keyCode: 63, modifiers: 0)
  static let legacyRecord = ShortcutBinding(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
  var isFn: Bool { keyCode == 63 }
  var label: String {
    let keys: [UInt32: String] = [0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"−", 28:"8", 29:"0", 31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 36:"↩", 48:"⇥"]
    return (modifiers & UInt32(controlKey) != 0 ? "⌃" : "")
      + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "")
      + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "")
      + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "")
      + (isFn ? "Fn" : keys[keyCode] ?? "Key \(keyCode)")
  }
  static func from(_ event: NSEvent) -> ShortcutBinding {
    let flags = event.modifierFlags
    var modifiers: UInt32 = 0
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    return ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
  }
  func matchesModifiers(_ flags: CGEventFlags) -> Bool {
    var actual: UInt32 = 0
    if flags.contains(.maskControl) { actual |= UInt32(controlKey) }
    if flags.contains(.maskAlternate) { actual |= UInt32(optionKey) }
    if flags.contains(.maskShift) { actual |= UInt32(shiftKey) }
    if flags.contains(.maskCommand) { actual |= UInt32(cmdKey) }
    return actual == modifiers
  }

  var validationError: String? {
    guard modifiers != 0, keyCode != 53,
          ![54, 55, 56, 57, 58, 59, 60, 61, 62].contains(keyCode),
          !(modifiers == UInt32(cmdKey) && [12, 13, 4, 46, 48, 49].contains(keyCode)),
          !(modifiers == UInt32(controlKey) && keyCode == 49),
          !(modifiers == UInt32(cmdKey | shiftKey) && [20, 21, 23].contains(keyCode)) else {
      return "请使用带修饰键的组合，并避开系统保留快捷键。"
    }
    // Common editing commands are application menu shortcuts, not system symbolic hotkeys.
    if (modifiers == UInt32(cmdKey) && [0, 1, 3, 6, 7, 8, 9, 17, 31, 35, 45].contains(keyCode))
      || (modifiers == UInt32(cmdKey | shiftKey) && keyCode == 6)
      || (modifiers == UInt32(cmdKey | optionKey | shiftKey) && keyCode == 9) {
      return "该组合用于常用的复制、粘贴或编辑操作，请换一个快捷键。"
    }
    return nil
  }

  @MainActor static func enabledSystemBindings() -> [ShortcutBinding] {
    var hotkeys: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&hotkeys) == noErr,
          let values = hotkeys?.takeRetainedValue() as? [[String: Any]] else { return [] }
    return values.compactMap { value in
      guard (value[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
            let code = value[kHISymbolicHotKeyCode as String] as? NSNumber,
            let modifiers = value[kHISymbolicHotKeyModifiers as String] as? NSNumber else { return nil }
      return ShortcutBinding(keyCode: code.uint32Value, modifiers: modifiers.uint32Value)
    }
  }
}

@MainActor @Observable final class HotkeyService {
  var lastError: String?
  var onPress: ((ShortcutAction, TimeInterval) -> Void)?
  var onRelease: ((ShortcutAction, TimeInterval) -> Void)?
  var onCancel: (() -> Void)?
  var onRecordInterrupt: ((ShortcutAction) -> Void)?
  private(set) var fnEnabled = false
  private var fnMonitor: FnKeyMonitor?
  private var fnMonitorID: UUID?
  private var fnBindings: [ShortcutAction: ShortcutBinding] = [:]
  private var suspended = false
  private var registrations: [ShortcutAction: EventHotKeyRef] = [:]
  private var handler: EventHandlerRef?
  private var escapeRegistration: EventHotKeyRef?
  private var held: Set<ShortcutAction> = []
  private let signature: OSType = 0x54455353

  init() {
    var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                  EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
    InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
      guard let event, let context else { return OSStatus(eventNotHandledErr) }
      var identifier = EventHotKeyID()
      guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
      let service = Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue()
      let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
      let time = GetEventTime(event)
      MainActor.assumeIsolated { service.handle(identifier.id, pressed: pressed, at: time) }
      return noErr
    }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  func register(_ bindings: [ShortcutAction: ShortcutBinding]) {
    suspended = false
    var errors: [String] = []
    for action in ShortcutAction.allCases {
      _ = set(action, binding: bindings[action])
      if let lastError { errors.append(lastError) }
    }
    lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
  }

  func suspend() {
    suspended = true
    fnMonitorID = nil
    fnMonitor?.stop()
    fnEnabled = false
    for reference in registrations.values { UnregisterEventHotKey(reference) }
    registrations.removeAll()
    held.removeAll()
    enableEscape(false)
  }

  func set(_ action: ShortcutAction, binding: ShortcutBinding?) -> Bool {
    lastError = nil
    guard ShortcutAction.allCases.contains(action) else { return false }
    guard action != .record || binding == .fn else {
      lastError = "基础语音输入固定使用 Fn。"
      return false
    }
    guard let binding else {
      if fnBindings.removeValue(forKey: action) != nil { rebuildFnMonitor() }
      if let ref = registrations.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
      held.remove(action)
      return true
    }
    if binding.isFn {
      guard action.recordMode != nil else { lastError = "Fn 用于语音输入；其他动作请使用组合键。"; return false }
      if let ref = registrations.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
      held.remove(action)
      fnBindings[action] = binding
      rebuildFnMonitor()
      return true
    }
    if let error = binding.validationError {
      lastError = error
      return false
    }
    guard !ShortcutBinding.enabledSystemBindings().contains(binding) else {
      lastError = "该快捷键已用于系统功能，请更换组合或在键盘设置中调整。"
      return false
    }
    if fnBindings.removeValue(forKey: action) != nil { rebuildFnMonitor() }
    let old = registrations.removeValue(forKey: action)
    if let old { UnregisterEventHotKey(old) }
    var reference: EventHotKeyRef?
    let id = EventHotKeyID(signature: signature, id: UInt32(ShortcutAction.allCases.firstIndex(of: action)! + 1))
    let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, id, GetApplicationEventTarget(), 0, &reference)
    guard status == noErr, let reference else {
      lastError = "快捷键注册失败（\(status)），可能与系统或其他应用冲突。"
      return false
    }
    registrations[action] = reference
    return true
  }

  private func rebuildFnMonitor() {
    fnMonitor?.stop(); fnMonitor = nil; fnMonitorID = nil; fnEnabled = false
    guard !fnBindings.isEmpty else { return }
    let id = UUID()
    fnMonitorID = id
    fnMonitor = FnKeyMonitor(bindings: fnBindings) { [weak self] action, pressed, time in
      guard let self, !self.suspended, self.fnMonitorID == id else { return }
      if let pressed {
        self.handle(UInt32(ShortcutAction.allCases.firstIndex(of: action)! + 1), pressed: pressed, at: time)
      } else if self.held.remove(action) != nil { self.onRecordInterrupt?(action) }
    }
    refreshFn()
  }

  func refreshFn() {
    guard !suspended, let fnMonitor else { return }
    let wasEnabled = fnEnabled
    fnEnabled = fnMonitor.start()
    if !fnEnabled {
      lastError = "Fn 尚未启用：请允许 Tess 的辅助功能权限；也可改用组合键。"
      if wasEnabled {
        for action in fnBindings.keys { onRecordInterrupt?(action) }
      }
    } else if lastError?.hasPrefix("Fn 尚未启用") == true { lastError = nil }
  }

  func interruptForSessionChange() {
    fnMonitor?.stop()
    fnEnabled = false
    held.removeAll()
  }

  func enableEscape(_ enabled: Bool) {
    if let reference = escapeRegistration { UnregisterEventHotKey(reference); escapeRegistration = nil }
    if enabled {
      var reference: EventHotKeyRef?
      if RegisterEventHotKey(53, 0, EventHotKeyID(signature: signature, id: 99), GetApplicationEventTarget(), 0, &reference) == noErr {
        escapeRegistration = reference
      }
    }
  }

  private func handle(_ identifier: UInt32, pressed: Bool, at time: TimeInterval) {
    if identifier == 99 { if pressed { onCancel?() }; return }
    guard identifier > 0, identifier <= ShortcutAction.allCases.count else { return }
    let action = ShortcutAction.allCases[Int(identifier) - 1]
    if pressed {
      guard held.insert(action).inserted else { return }
      onPress?(action, time)
    } else {
      guard held.remove(action) != nil else { return }
      onRelease?(action, time)
    }
  }
}

// Only Fn modifier events and Globe key code 179 are interpreted; ordinary keys pass through.
@MainActor final class FnKeyMonitor {
  private let bindings: [ShortcutAction: ShortcutBinding]
  private let handler: (ShortcutAction, Bool?, TimeInterval) -> Void
  private var eventTap: CFMachPort?
  private var source: CFRunLoopSource?
  private var fnDown = false
  private var heldAction: ShortcutAction?
  private var pendingAction: ShortcutAction?
  private var pendingModifiers: UInt32 = 0
  private var pressedAt: TimeInterval = 0
  private var pendingPressID: UUID?
  private var capturedFn = false
  private var capturedGlobe: Bool?

  init(bindings: [ShortcutAction: ShortcutBinding], handler: @escaping (ShortcutAction, Bool?, TimeInterval) -> Void) {
    self.bindings = bindings
    self.handler = handler
  }

  func start() -> Bool {
    guard AXIsProcessTrusted() else { stop(); return false }
    if eventTap != nil { return true }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
      options: .defaultTap, eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue
        | 1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue),
      callback: { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let swallow = MainActor.assumeIsolated {
          Unmanaged<FnKeyMonitor>.fromOpaque(context).takeUnretainedValue().process(type, event) == nil
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
      }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { CFMachPortInvalidate(tap); return false }
    eventTap = tap
    self.source = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    let interruptedAction = heldAction
    if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    eventTap = nil; source = nil
    resetGesture()
    capturedGlobe = nil
    if let interruptedAction { handler(interruptedAction, nil, ProcessInfo.processInfo.systemUptime) }
  }

  // Internal so checks can drive synthetic events without starting a live tap.
  func process(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let time = TimeInterval(event.timestamp) / 1_000_000_000
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let heldAction { handler(heldAction, nil, time) }
      resetGesture()
      capturedGlobe = nil
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    if type == .keyDown || type == .keyUp {
      guard event.getIntegerValueField(.keyboardEventKeycode) == 179 else { return Unmanaged.passUnretained(event) }
      // Globe's pair can precede or follow key 63. Only key 63 triggers recording.
      // A fresh down decides its own pair, so a Fn hold without Globe leaves no stale capture.
      if type == .keyDown {
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
          capturedGlobe = bindings.values.contains { $0.matchesModifiers(event.flags) }
        }
        return capturedGlobe == true ? nil : Unmanaged.passUnretained(event)
      }
      let swallow = capturedGlobe == true
      capturedGlobe = nil
      return swallow ? nil : Unmanaged.passUnretained(event)
    }
    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    let isFnEvent = event.getIntegerValueField(.keyboardEventKeycode) == 63
    if isFnEvent {
      let down = event.flags.contains(.maskSecondaryFn)
      if down, !fnDown {
        fnDown = true
        pressedAt = time
        selectPendingAction(event.flags)
        capturedFn = pendingAction != nil
        let id = UUID()
        pendingPressID = id
        // Let adjacent Fn/modifier presses settle into one mode before starting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
          guard let self, self.pendingPressID == id else { return }
          self.commitPendingPress()
        }
      } else if !down, fnDown {
        let swallow = capturedFn
        commitPendingPress()
        if let heldAction { handler(heldAction, false, time) }
        resetGesture()
        return swallow ? nil : Unmanaged.passUnretained(event)
      }
    } else if fnDown, pendingPressID != nil {
      let modifiers = Self.modifiers(event.flags)
      // Removing a chord's modifier cannot turn it back into a bare-Fn trigger.
      if modifiers != pendingModifiers, modifiers & pendingModifiers == pendingModifiers {
        selectPendingAction(event.flags)
        capturedFn = capturedFn || pendingAction != nil
      }
    }
    return isFnEvent && capturedFn ? nil : Unmanaged.passUnretained(event)
  }

  func commitPendingPress() {
    guard pendingPressID != nil, fnDown else { return }
    pendingPressID = nil
    heldAction = pendingAction
    pendingAction = nil
    if let heldAction { handler(heldAction, true, pressedAt) }
  }

  private func selectPendingAction(_ flags: CGEventFlags) {
    pendingModifiers = Self.modifiers(flags)
    pendingAction = ShortcutAction.allCases.first { bindings[$0]?.matchesModifiers(flags) == true }
  }

  private static func modifiers(_ flags: CGEventFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.maskControl) { result |= UInt32(controlKey) }
    if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
    if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
    if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
    return result
  }

  private func resetGesture() {
    pendingPressID = nil; pendingAction = nil; heldAction = nil
    fnDown = false; capturedFn = false; pendingModifiers = 0
  }
}

struct RecordKeyGesture {
  enum Phase { case idle, loading, recording, busy }
  enum Action: Equatable { case none, start, stop, cancel }
  private var pressedAt: TimeInterval?
  private var latched = false

  mutating func press(at time: TimeInterval, phase: Phase, automatic: Bool, hold: Bool) -> Action {
    if phase == .idle { pressedAt = time; latched = false; return .start }
    if phase == .recording, automatic || !hold { reset(); return .stop }
    if phase == .loading, latched || !hold { reset(); return .cancel }
    return .none
  }

  mutating func release(at time: TimeInterval, phase: Phase, automatic: Bool, hold: Bool) -> Action {
    guard let pressedAt else { return .none }
    self.pressedAt = nil
    guard hold else { return .none }
    if automatic, time - pressedAt < 0.25, phase == .loading || phase == .recording {
      latched = true
      return .none
    }
    latched = false
    return phase == .loading ? .cancel : phase == .recording ? .stop : .none
  }

  mutating func reset() { pressedAt = nil; latched = false }
}
