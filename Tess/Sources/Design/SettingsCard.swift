import SwiftUI

/// A quiet paper surface for a group of related settings.
struct SettingsCard<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.3)
        .foregroundStyle(contrast == .increased ? SettingsTheme.secondary : SettingsTheme.muted)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 6)

      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 10)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(SettingsTheme.card.opacity(0.86))
        .shadow(color: SettingsTheme.foreground.opacity(0.025), radius: 14, x: 0, y: 3)
    }
    .overlay {
      if contrast == .increased {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(SettingsTheme.foreground.opacity(0.28), lineWidth: 1)
      }
    }
  }
}
