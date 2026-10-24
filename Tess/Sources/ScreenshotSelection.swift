import AppKit
import ScreenCaptureKit

struct ScreenshotScreen {
  let frame: CGRect
  let image: CGImage
}

struct ScreenshotPlacement {
  let imageURL: URL
  let frame: CGRect
  let screenFrame: CGRect
  var screens: [ScreenshotScreen]
}

struct ScreenshotSelection {
  let image: CGImage
  let frame: CGRect
  let screenFrame: CGRect
}

@MainActor
final class ScreenshotSelectionController {
  private var windows: [ScreenshotWindow] = []
  private var continuation: CheckedContinuation<ScreenshotSelection?, Never>?

  static func captureScreens() async throws -> [ScreenshotScreen] {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    var snapshots: [ScreenshotScreen] = []
    for screen in NSScreen.screens {
      try Task.checkCancellation()
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
      let configuration = SCStreamConfiguration()
      configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
      configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
      configuration.showsCursor = false
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration)
      snapshots.append(ScreenshotScreen(frame: screen.frame, image: image))
    }
    guard !snapshots.isEmpty else { throw CocoaError(.fileReadUnknown) }
    return snapshots
  }

  func select(screens: [ScreenshotScreen]) async -> ScreenshotSelection? {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      for screen in screens {
        let window = ScreenshotWindow(frame: screen.frame, onCancel: { [weak self] in self?.dismiss() })
        window.contentView = ScreenshotSelectionView(screen: screen) { [weak self] selection in
          guard let self, let pending = self.continuation else { return }
          self.continuation = nil
          // Keep the selection visible until the editor has taken its place.
          pending.resume(returning: selection)
        }
        windows.append(window)
        window.orderFrontRegardless()
      }
      (windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? windows.first)?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  func dismiss() {
    let pending = continuation
    continuation = nil
    for window in windows { window.orderOut(nil); window.contentView = nil }
    windows = []
    pending?.resume(returning: nil)
  }
}

@MainActor
private final class ScreenshotSelectionView: NSView {
  private let screen: ScreenshotScreen
  private let background: NSImage
  private let onSelection: (ScreenshotSelection) -> Void
  private var start: CGPoint?
  private var selection: CGRect?
  override var isFlipped: Bool { true }

  init(screen: ScreenshotScreen, onSelection: @escaping (ScreenshotSelection) -> Void) {
    self.screen = screen
    background = NSImage(cgImage: screen.image, size: screen.frame.size)
    self.onSelection = onSelection
    super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    NSColor.black.withAlphaComponent(0.48).setFill()
    bounds.fill()
    if let selection {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: selection).addClip()
      background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
      NSGraphicsContext.restoreGraphicsState()
      NSColor.white.setStroke()
      NSBezierPath(rect: selection).stroke()
    }
  }

  private func point(_ event: NSEvent) -> CGPoint {
    let point = convert(event.locationInWindow, from: nil)
    return CGPoint(x: min(max(0, point.x), bounds.width), y: min(max(0, point.y), bounds.height))
  }

  override func mouseDown(with event: NSEvent) {
    start = point(event)
    selection = nil
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start else { return }
    let end = point(event)
    selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                       width: abs(end.x - start.x), height: abs(end.y - start.y))
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    mouseDragged(with: event)
    start = nil
    guard let selection, selection.width >= 2, selection.height >= 2 else { return }
    let scaleX = CGFloat(screen.image.width) / bounds.width
    let scaleY = CGFloat(screen.image.height) / bounds.height
    let pixels = CGRect(x: selection.minX * scaleX, y: selection.minY * scaleY,
                        width: selection.width * scaleX, height: selection.height * scaleY).integral
      .intersection(CGRect(x: 0, y: 0, width: screen.image.width, height: screen.image.height))
    guard let image = screen.image.cropping(to: pixels) else { return }
    let frame = CGRect(x: screen.frame.minX + pixels.minX / scaleX,
                       y: screen.frame.maxY - pixels.maxY / scaleY,
                       width: pixels.width / scaleX, height: pixels.height / scaleY)
    onSelection(ScreenshotSelection(image: image, frame: frame, screenFrame: screen.frame))
  }
}

@MainActor
final class ScreenshotWindow: NSWindow {
  var onCancel: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  init(frame: CGRect, onCancel: @escaping () -> Void) {
    super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    self.onCancel = onCancel
    backgroundColor = .clear
    isOpaque = false
    hasShadow = false
    isReleasedWhenClosed = false
    level = .screenSaver
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    setFrame(frame, display: false)
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown {
      let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
      if event.keyCode == 53 || (event.keyCode == 13 && modifiers == .command) {
        onCancel?()
        return
      }
    }
    super.sendEvent(event)
  }
}
