import SwiftUI

/// The capsule button used by Settings preview and action rows.
struct SettingsButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(SettingsTheme.foreground)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(SettingsTheme.accent.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
      .overlay {
        Capsule().stroke(SettingsTheme.border, lineWidth: 1)
      }
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.45)
  }
}
