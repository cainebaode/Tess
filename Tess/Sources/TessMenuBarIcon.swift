import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class TessMenuIconVisibility {
  var visible = false
}

struct TessMenuBarIcon: View {
  var app: AppModel
  var visibility: TessMenuIconVisibility

  private var motion: TessIconMotion {
    if app.phase == .recording { return .listening }
    if app.phase == .idle { return TessIconMotion(phase: app.hudFeedback) }
    return .still
  }

  var body: some View {
    TessStateIcon(menuBar: true, size: 18, motion: motion, isActive: visibility.visible)
      .frame(width: 22, height: 22)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// A decoration inside the original status button; AppKit retains menu hit testing and focus.
@MainActor final class TessMenuBarIconHost: NSHostingView<TessMenuBarIcon> {
  private let visibility: TessMenuIconVisibility
  convenience init(app: AppModel) {
    let visibility = TessMenuIconVisibility()
    self.init(rootView: TessMenuBarIcon(app: app, visibility: visibility))
  }

  required init(rootView: TessMenuBarIcon) {
    visibility = rootView.visibility
    super.init(rootView: rootView)
    sizingOptions = []
  }

  @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
  override var acceptsFirstResponder: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stop()
    guard let window else { return }
    NotificationCenter.default.addObserver(self, selector: #selector(refreshVisibility),
                                           name: NSWindow.didChangeOcclusionStateNotification, object: window)
    refreshVisibility()
  }

  override func viewDidHide() { super.viewDidHide(); visibility.visible = false }
  override func viewDidUnhide() { super.viewDidUnhide(); refreshVisibility() }

  @objc private func refreshVisibility() {
    visibility.visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
      && !isHiddenOrHasHiddenAncestor
  }

  func stop() {
    visibility.visible = false
    NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
  }
}
