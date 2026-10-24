import AppKit
import SwiftUI

/// Tess's warm paper surfaces and forest-green brand palette.
enum SettingsTheme {
  static let backgroundColor = NSColor(red: 250 / 255, green: 249 / 255, blue: 240 / 255, alpha: 1)
  static let background = Color(nsColor: backgroundColor)
  static let sidebar = Color(red: 240 / 255, green: 242 / 255, blue: 231 / 255)
  static let card = Color(red: 255 / 255, green: 254 / 255, blue: 248 / 255)
  static let foregroundColor = NSColor(red: 23 / 255, green: 61 / 255, blue: 46 / 255, alpha: 1)
  static let foreground = Color(nsColor: foregroundColor)
  static let secondary = Color(red: 83 / 255, green: 103 / 255, blue: 91 / 255)
  static let muted = Color(red: 104 / 255, green: 121 / 255, blue: 108 / 255)
  static let border = foreground.opacity(0.12)
  static let accent = Color(nsColor: accentColor)
  static let accentColor = NSColor(red: 53 / 255, green: 104 / 255, blue: 74 / 255, alpha: 1)
  static let leaf = Color(red: 174 / 255, green: 217 / 255, blue: 120 / 255)
  static let warning = Color(red: 154 / 255, green: 76 / 255, blue: 33 / 255)
  static let hudBackground = Color(red: 16 / 255, green: 47 / 255, blue: 37 / 255)
  static let hudForeground = Color(red: 247 / 255, green: 248 / 255, blue: 237 / 255)
}
