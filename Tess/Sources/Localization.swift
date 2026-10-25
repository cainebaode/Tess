import Foundation

enum InterfaceLanguage: String, Codable, CaseIterable {
  case system, chinese, english
  var usesChinese: Bool {
    self == .chinese || (self == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
  }
}

struct AppPreferences: Codable {
  var language: InterfaceLanguage = .system
  var holdToRecord = true
  var alwaysPreview = false
  var textMode: TextMode = .raw
  var textPrompts: TextPrompts? = nil
  var recognitionLanguage = "auto"
  var bindings: [ShortcutAction: ShortcutBinding] = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaults) })
  var shortcutVersion: Int? = nil
  var completedOnboarding = false
  var onboardingStep: Int? = nil
  var onboardingPracticePassed: Bool? = nil
  var asrModel: ASRModel? = nil
  var microphoneID: UInt32? = nil

  mutating func migrate() {
    guard (shortcutVersion ?? 0) < 2 else { return }
    if shortcutVersion == nil, bindings[.record] == .legacyRecord { bindings[.record] = .fn }
    for action in [ShortcutAction.recordLight, .recordList, .recordPolish] {
      if bindings[action] == nil, !bindings.values.contains(action.defaults) { bindings[action] = action.defaults }
    }
    alwaysPreview = false
    shortcutVersion = 2
  }
}

struct SavedResult: Codable {
  var id = UUID()
  var createdAt = Date()
  var original: String
  var output: String
  var candidate: String?
  var imageName: String?
  var mode: TextMode
  var message: String?
  var origin: String
}
