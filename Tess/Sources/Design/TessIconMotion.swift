import SwiftUI

enum TessIconMotion: Equatable {
  case still, listening, completed

  init(phase: HUDPhase) {
    switch phase {
    case .recording: self = .listening
    case .completed, .copied: self = .completed
    default: self = .still
    }
  }
}

/// Finite facial animation. Every frame uses the same canvas and fixed placement.
struct TessStateIcon: View {
  var menuBar = false
  var size: CGFloat
  var motion: TessIconMotion
  var isActive = true
  var previewReduceMotion = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var frame = Frame.rest
  @State private var playback: Task<Void, Never>?

  private enum Frame: Int {
    case rest, blink, turn
  }

  private var canAnimate: Bool { isActive && !reduceMotion && !previewReduceMotion }

  // NSImages are cached by TessBrand; evaluating the list mounts all three frames
  // before the first action, without rebuilding image data on each frame change.
  private var frames: [NSImage] {
    menuBar
      ? [TessBrand.menuBar, TessBrand.menuBarBlink, TessBrand.menuBarTurn]
      : [TessBrand.avatar, TessBrand.avatarBlink, TessBrand.avatarTurn]
  }

  var body: some View {
    let visibleFrame = canAnimate && motion != .still ? frame : .rest
    Image(nsImage: frames[visibleFrame.rawValue])
      .resizable().interpolation(.high).scaledToFit()
      .frame(width: size, height: size)
      .transaction { $0.animation = nil }
      .accessibilityHidden(true)
      .onChange(of: motion) { _, _ in play() }
      .onChange(of: canAnimate) { _, allowed in if !allowed { stop() } }
      .onDisappear { stop() }
  }

  private func play() {
    stop()
    guard canAnimate, motion != .still else { return }
    let sequence: [(Frame, Double)] = motion == .listening
      ? [(.rest, 0.4), (.turn, 0.4), (.rest, 2.2), (.blink, 0.12)]
      : [(.blink, 0.12)]
    playback = Task { @MainActor in
      for (next, duration) in sequence {
        guard !Task.isCancelled else { return }
        frame = next
        do { try await Task.sleep(for: .seconds(duration)) }
        catch { return }
      }
      guard !Task.isCancelled else { return }
      frame = .rest
      playback = nil
    }
  }

  private func stop() {
    playback?.cancel()
    playback = nil
    frame = .rest
  }
}
