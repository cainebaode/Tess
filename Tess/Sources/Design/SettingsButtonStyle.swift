import SwiftUI

/// Compact, softly raised actions shared by Tess's windows.
struct SettingsButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(SettingsTheme.foreground)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(SettingsTheme.accent.opacity(configuration.isPressed ? 0.12 : isHovered && isEnabled ? 0.08 : 0.045))
          .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(SettingsTheme.foreground.opacity(0.04), lineWidth: 0.5)
      }
      .opacity(isEnabled ? 1 : 0.45)
      .onHover { isHovered = $0 }
  }
}

struct SettingsNavigationStyle: ButtonStyle {
  var isSelected: Bool
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isSelected ? SettingsTheme.foreground : SettingsTheme.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(isSelected ? SettingsTheme.leaf.opacity(0.2)
                : .white.opacity(isHovered || configuration.isPressed ? 0.4 : 0))
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .onHover { isHovered = $0 }
  }
}
