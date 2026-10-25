import AppKit
import SwiftUI

/// Tess's warm paper surfaces, frosted chrome and forest-green brand palette.
enum SettingsTheme {
  static let backgroundColor = NSColor(red: 250 / 255, green: 249 / 255, blue: 240 / 255, alpha: 1)
  static let background = Color(nsColor: backgroundColor)
  static let sidebar = Color(red: 240 / 255, green: 242 / 255, blue: 231 / 255)
  static let card = Color(red: 255 / 255, green: 254 / 255, blue: 248 / 255)
  static let foregroundColor = NSColor(red: 23 / 255, green: 61 / 255, blue: 46 / 255, alpha: 1)
  static let foreground = Color(nsColor: foregroundColor)
  static let secondary = Color(red: 83 / 255, green: 103 / 255, blue: 91 / 255)
  static let muted = Color(red: 104 / 255, green: 121 / 255, blue: 108 / 255)
  static let border = foreground.opacity(0.09)
  static let accent = Color(nsColor: accentColor)
  static let accentColor = NSColor(red: 53 / 255, green: 104 / 255, blue: 74 / 255, alpha: 1)
  static let leaf = Color(red: 174 / 255, green: 217 / 255, blue: 120 / 255)
  static let warning = Color(red: 154 / 255, green: 76 / 255, blue: 33 / 255)
  static let hudBackground = Color(red: 16 / 255, green: 47 / 255, blue: 37 / 255)
  static let hudForeground = Color(red: 247 / 255, green: 248 / 255, blue: 237 / 255)
}

/// One warm, softly tinted surface shared by the window chrome and content.
struct SettingsWindowBackdrop: View {
  var body: some View {
    SettingsDesktopMaterial()
      .overlay {
        LinearGradient(colors: [
          Color(red: 232 / 255, green: 237 / 255, blue: 224 / 255).opacity(0.85),
          SettingsTheme.background.opacity(0.9),
          Color(red: 240 / 255, green: 237 / 255, blue: 224 / 255).opacity(0.8)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      .allowsHitTesting(false)
  }
}

/// The sidebar gently fades into the shared canvas, without a reflective rim.
struct SettingsSidebarBackdrop: View {
  var body: some View {
    Rectangle().fill(.ultraThinMaterial)
      .overlay(SettingsTheme.sidebar.opacity(0.12))
      .mask {
        LinearGradient(stops: [
          .init(color: .white, location: 0),
          .init(color: .white, location: 0.86),
          .init(color: .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing)
      }
      .mask {
        LinearGradient(stops: [
          .init(color: .clear, location: 0),
          .init(color: .white, location: 0.035),
          .init(color: .white, location: 0.965),
          .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
      }
      .allowsHitTesting(false)
  }
}

private struct SettingsDesktopMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
