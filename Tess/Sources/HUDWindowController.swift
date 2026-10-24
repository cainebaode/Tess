import AppKit
import Observation
import SwiftUI

@MainActor @Observable private final class HUDVisibility {
  var visible = false
}

/// A nonactivating, top-anchored panel. Only its visible lifetime owns a SwiftUI tree.
@MainActor final class HUDWindowController {
  private let panel: FloatingPanel
  private let visibility = HUDVisibility()
  private var dismissal: Task<Void, Never>?
  private var presentation: Task<Void, Never>?
  private var session: UUID?
  private var topAnchor = CGPoint.zero
  private var displayID: CGDirectDisplayID?
  private var displayObserver: NSObjectProtocol?
  var window: NSWindow { panel }

  init() {
    panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.isReleasedWhenClosed = false
    panel.appearance = NSAppearance(named: .darkAqua)
    displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.panel.isVisible else { return }
        self.place(screenID: self.displayID)
      }
    }
  }

  func show(app: AppModel) {
    dismissal?.cancel()
    presentation?.cancel()
    if !panel.isVisible || (app.hudSessionID != nil && session != app.hudSessionID) {
      session = app.hudSessionID
      place(screenID: app.hudScreenID)
    }
    if !(panel.contentView is NSHostingView<LiveHUD>) {
      let view = NSHostingView(rootView: LiveHUD(app: app, visibility: visibility) { [weak self] height in
        guard let self else { return }
        self.resize(height: height)
      })
      view.sizingOptions = []
      panel.contentView = view
    }
    panel.ignoresMouseEvents = false
    panel.orderFrontRegardless()
    presentation = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled else { return }
      self?.visibility.visible = true
    }
  }

  func hide(immediately: Bool = false) {
    dismissal?.cancel()
    presentation?.cancel()
    visibility.visible = false
    panel.ignoresMouseEvents = true
    if immediately { tearDown(); return }
    dismissal = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      self?.tearDown()
    }
  }

  private func tearDown() {
    panel.orderOut(nil)
    panel.contentView = nil
    session = nil
  }

  private func place(screenID: CGDirectDisplayID?) {
    let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID }
      ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
      ?? NSScreen.main
    guard let screen else { return }
    displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    // safeAreaInsets protects the camera housing even with an auto-hidden menu bar.
    topAnchor = CGPoint(x: screen.visibleFrame.midX,
                        y: min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 8)
    resize(height: panel.frame.height)
  }

  private func resize(height: CGFloat) {
    let size = NSSize(width: 380, height: max(90, min(430, ceil(height))))
    let frame = NSRect(x: topAnchor.x - size.width / 2, y: topAnchor.y - size.height, width: size.width, height: size.height)
    if panel.frame != frame { panel.setFrame(frame, display: true) }
  }
}

private struct LiveHUD: View {
  var app: AppModel
  var visibility: HUDVisibility
  var onHeight: (CGFloat) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HUDView(snapshot: app.hudSnapshot,
            onStop: { app.stopRecording() }, onCancel: { app.cancel() },
            onRetry: { app.retryFromHUD() },
            onResult: { app.hideHUD?(); app.showResult() }, onConfirm: { app.confirmInsertion() },
            onSettings: { app.openScreenCaptureSettings() }, isVisible: visibility.visible)
      .opacity(visibility.visible ? 1 : 0)
      .scaleEffect(reduceMotion ? 1 : visibility.visible ? 1 : 0.94, anchor: .top)
      .offset(y: reduceMotion || visibility.visible ? 0 : -4)
      .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.05), value: visibility.visible)
      .padding(16)
      .fixedSize(horizontal: true, vertical: true)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .allowsHitTesting(visibility.visible)
      .accessibilityHidden(!visibility.visible)
  }
}
