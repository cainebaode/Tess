import AppKit
@preconcurrency import ApplicationServices
import Carbon
import CryptoKit

// Full fields exist only during comparison. Retained boundaries are lengths and hashes.
struct SpeechInsertionAnchor: Sendable {
    let prefixLength: Int
    let suffixLength: Int
    let prefixHash: String
    let suffixHash: String

    static func verify(before: String, selection: NSRange, inserted: String, after: String) -> SpeechInsertionAnchor? {
        guard before.count <= 8_000, after.count <= 8_000, !inserted.isEmpty,
              let selected = characterRange(selection, in: before) else { return nil }
        let prefix = String(before[..<selected.lowerBound]), suffix = String(before[selected.upperBound...])
        guard after == prefix + inserted + suffix, after != before,
              after.components(separatedBy: inserted).count == 2 else { return nil }
        return .init(prefixLength: prefix.utf16.count, suffixLength: suffix.utf16.count,
                     prefixHash: digest(prefix), suffixHash: digest(suffix))
    }

    func extract(from field: String) -> String? {
        let length = field.utf16.count - prefixLength - suffixLength
        guard field.count <= 8_000, length > 0,
              let range = Self.characterRange(NSRange(location: prefixLength, length: length), in: field) else { return nil }
        let prefix = String(field[..<range.lowerBound]), suffix = String(field[range.upperBound...])
        guard Self.digest(prefix) == prefixHash, Self.digest(suffix) == suffixHash else { return nil }
        let segment = String(field[range])
        guard !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              field.components(separatedBy: segment).count == 2 else { return nil }
        return segment
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func characterRange(_ range: NSRange, in text: String) -> Range<String.Index>? {
        let count = text.utf16.count
        guard range.location >= 0, range.length >= 0, range.location <= count, range.length <= count - range.location else { return nil }
        let boundaries = Dictionary(uniqueKeysWithValues: (Array(text.indices) + [text.endIndex]).map { ($0.utf16Offset(in: text), $0) })
        guard let start = boundaries[range.location], let end = boundaries[range.location + range.length] else { return nil }
        return start..<end
    }
}

// Separate from InputInteractionGuard: editing never posts keys or touches the clipboard.
@MainActor final class SpeechInputObservation {
    private var element: AXUIElement?
    private var application: AXUIElement?
    private var window: AXUIElement?
    private var processID: pid_t?
    private var before: String?
    private var selection: NSRange?
    private var inserted = ""
    private var postedAt: TimeInterval?
    private var anchor: SpeechInsertionAnchor?
    private var observer: AXObserver?
    private var registrations: [(AXUIElement, String)] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var debounce: Task<Void, Never>?
    private var startedAt: TimeInterval?
    private var stopped = false
    private let onEdit: (String) -> Void

    #if TESS_INTERNAL_CHECKS
    // Replaces only AX/clock I/O for isolated lifecycle checks; never in installed builds.
    final class Fixture {
        var field: String
        var identityValid = true
        var notificationsSupported = true
        var time: TimeInterval = 0
        init(field: String) { self.field = field }
    }
    private var fixture: Fixture?
    var isObservingForCheck: Bool { !stopped && anchor != nil && startedAt != nil }
    func prepareForCheck(before: String, selection: NSRange, inserted: String, fixture: Fixture) {
        self.fixture = fixture; self.before = before; self.selection = selection; self.inserted = inserted
        postedAt = fixture.time
    }
    func notifyForCheck() { changed(kAXValueChangedNotification) }
    func tickForCheck() { if !validIdentity() || expired { stop() } }
    #endif

    private var now: TimeInterval {
        #if TESS_INTERNAL_CHECKS
        if let fixture { return fixture.time }
        #endif
        return ProcessInfo.processInfo.systemUptime
    }

    init(onEdit: @escaping (String) -> Void) { self.onEdit = onEdit }

    // Called immediately before the already-authorized paste, only for a normal AX input.
    func prepare(element: AXUIElement, processID: pid_t, range: CFRange, text: String) {
        guard !stopped, !text.isEmpty else { return }
        self.element = element; self.processID = processID
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.1)
        AXUIElementSetMessagingTimeout(element, 0.1)
        self.application = application
        window = Self.elementAttribute(application, kAXFocusedWindowAttribute)
        guard validIdentity(), let before = readField(), before.count <= 8_000,
              let selected = Self.selectedRange(element), selected.location == range.location,
              selected.length == range.length, SpeechInsertionAnchor.characterRange(selected, in: before) != nil else { stop(); return }
        self.before = before; selection = selected; inserted = text
        postedAt = now
    }

    func verifyAndStart() async {
        guard !stopped, let before, let selection, let postedAt else { stop(); return }
        // Includes the clipboard consumer's 0.5s window, with at most 1s total readback.
        for _ in 0..<6 {
            guard !Task.isCancelled, !stopped, validIdentity(),
                  now - postedAt <= 1 else { stop(); return }
            if let after = readField(), let proof = SpeechInsertionAnchor.verify(before: before, selection: selection, inserted: inserted, after: after) {
                anchor = proof
                self.before = nil; self.selection = nil; inserted = ""
                startNotifications()
                return
            }
            do { try await Task.sleep(for: .milliseconds(80)) } catch { stop(); return }
        }
        stop()
    }

    private func startNotifications() {
        #if TESS_INTERNAL_CHECKS
        if let fixture {
            guard fixture.notificationsSupported, validIdentity() else { stop(); return }
            startedAt = now
            return
        }
        #endif
        guard let processID, let element, let application else { stop(); return }
        var created: AXObserver?
        let error = AXObserverCreate(processID, { _, _, notification, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<SpeechInputObservation>.fromOpaque(context).takeUnretainedValue().changed(notification as String)
            }
        }, &created)
        guard error == .success, let created else { stop(); return }
        observer = created
        for (target, notification) in [(element, kAXValueChangedNotification),
                                        (application, kAXFocusedUIElementChangedNotification),
                                        (application, kAXFocusedWindowChangedNotification)] {
            guard AXObserverAddNotification(created, target, notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()) == .success else { stop(); return }
            registrations.append((target, notification))
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        startedAt = now
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        // Metadata/permission watchdog only. Text is read solely on this element's notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.validIdentity() || self.expired { self.stop() }
            }
        }
        guard validIdentity(), let field = readField(), anchor?.extract(from: field) != nil else { stop(); return }
    }

    private var expired: Bool {
        startedAt.map { now - $0 >= 120 } ?? true
    }

    private func changed(_ notification: String) {
        guard !stopped, !expired, validIdentity() else { stop(); return }
        guard notification == kAXValueChangedNotification else { return }
        // Validate each update; clearing/sending or edits outside the inserted range stop collection.
        guard let field = readField(), anchor?.extract(from: field) != nil else { stop(); return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, !self.stopped, !self.expired, self.validIdentity(),
                  let field = self.readField(), let text = self.anchor?.extract(from: field) else { self?.stop(); return }
            self.onEdit(text)
        }
    }

    private func validIdentity() -> Bool {
        #if TESS_INTERNAL_CHECKS
        if let fixture { return !stopped && fixture.identityValid }
        #endif
        guard !stopped, AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let processID, NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let application, let element, let window,
              let focus = Self.elementAttribute(application, kAXFocusedUIElementAttribute), CFEqual(focus, element),
              let currentWindow = Self.elementAttribute(application, kAXFocusedWindowAttribute), CFEqual(currentWindow, window),
              let role = Self.attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              Self.attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              Self.selectedRange(element) != nil else { return false }
        var settable = DarwinBoolean(false)
        var enabled: CFTypeRef?
        let enabledError = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
        return (enabledError == .attributeUnsupported || enabled as? Bool == true)
            && AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }

    private func readField() -> String? {
        #if TESS_INTERNAL_CHECKS
        if let fixture { return fixture.field.count <= 8_000 ? fixture.field : nil }
        #endif
        guard let element, let value = Self.attribute(element, kAXValueAttribute) as? String,
              value.count <= 8_000 else { return nil }
        return value
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    func stop() {
        stopped = true
        debounce?.cancel(); debounce = nil
        timer?.invalidate(); timer = nil
        if let observer {
            for (element, notification) in registrations { AXObserverRemoveNotification(observer, element, notification as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        registrations = []; workspaceObservers = []; observer = nil
        before = nil; selection = nil; inserted = ""; anchor = nil
        element = nil; application = nil; window = nil; processID = nil
    }

    isolated deinit { stop() }
}
