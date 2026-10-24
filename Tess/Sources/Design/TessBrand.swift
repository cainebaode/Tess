import SwiftUI
import CoreText

@MainActor enum TessBrand {
  static let avatar = image("TessAvatar")
  static let mascot = image("TessMascot")
  static let menuBar = image("TessMenuBar")
  static let avatarBlink = image("TessAvatarBlink")
  static let avatarTurn = image("TessAvatarTurn")
  static let menuBarBlink = image("TessMenuBarBlink")
  static let menuBarTurn = image("TessMenuBarTurn")
  static let wordmarkFontName = "SourceSans3-Semibold"

  private static let fontRegistration: Void = {
    guard let url = Bundle.main.url(forResource: wordmarkFontName, withExtension: "otf") else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }()

  static func registerFonts() { _ = fontRegistration }

  static func wordmarkFont(size: CGFloat) -> Font {
    registerFonts()
    return .custom(wordmarkFontName, size: size)
  }

  private static func image(_ name: String) -> NSImage {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: url) else { return NSImage() }
    image.isTemplate = false
    return image
  }
}

struct TessAvatar: View {
  var size: CGFloat = 32

  var body: some View {
    Image(nsImage: TessBrand.avatar)
      .resizable().interpolation(.high).scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

struct TessMascot: View {
  var height: CGFloat = 140

  var body: some View {
    Image(nsImage: TessBrand.mascot)
      .resizable().interpolation(.high).scaledToFit()
      .frame(width: height, height: height)
      .accessibilityHidden(true)
  }
}

struct TessWordmark: View {
  var size: CGFloat = 28

  var body: some View {
    Text("tess")
      .font(TessBrand.wordmarkFont(size: size))
      .fixedSize()
      .accessibilityLabel("Tess")
  }
}
