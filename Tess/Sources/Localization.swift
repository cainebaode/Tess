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
  var promptLibrary: [TextPrompt]? = nil
  var promptCatalogVersion: Int? = nil
  var custom1PromptID: String? = nil
  var custom2PromptID: String? = nil
  var recognitionLanguage = "auto"
  var bindings: [ShortcutAction: ShortcutBinding] = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaults) })
  var shortcutVersion: Int? = nil
  var completedOnboarding = false
  var onboardingStep: Int? = nil
  var onboardingPracticePassed: Bool? = nil
  var asrModel: ASRModel? = nil
  var microphoneID: UInt32? = nil

  var availablePrompts: [TextPrompt] { promptLibrary ?? TextPrompt.defaults }
  func prompt(for mode: TextMode) -> TextPrompt? {
    let id: String
    switch mode {
    case .custom1: id = custom1PromptID ?? "cleanup"
    case .custom2: id = custom2PromptID ?? "agent"
    default: return nil
    }
    return availablePrompts.first { $0.id == id }
  }

  mutating func migrate() {
    let hadSavedShortcuts = shortcutVersion != nil
    defer { migratePromptCatalog(preserveImplicitBindings: hadSavedShortcuts) }
    guard (shortcutVersion ?? 0) < 3 else { return }
    if (shortcutVersion ?? 0) < 2 {
      if shortcutVersion == nil, bindings[.record] == .legacyRecord { bindings[.record] = .fn }
      for action in [ShortcutAction.recordLight, .recordList, .recordPolish] {
        if bindings[action] == nil, !bindings.values.contains(action.defaults) { bindings[action] = action.defaults }
      }
      alwaysPreview = false
    }
    if promptLibrary == nil {
      var library = TextPrompt.legacyDefaults
      if let textPrompts {
        for mode in [TextMode.light, .list, .polish] {
          if let index = library.firstIndex(where: { $0.id == mode.rawValue }) {
            library[index].instructions = textPrompts.systemPrompt(for: mode)
          }
        }
      }
      promptLibrary = library
    }
    if let binding = bindings.removeValue(forKey: .recordLight) { bindings[.custom1] = binding }
    if let binding = bindings.removeValue(forKey: .recordPolish) { bindings[.custom2] = binding }
    bindings.removeValue(forKey: .recordList)
    bindings[.record] = .fn
    // Fn is reserved for plain dictation; conflicting legacy bindings stay unbound.
    for action in [ShortcutAction.custom1, .custom2] where bindings[action] == .fn {
      bindings[action] = nil
    }
    switch textMode {
    case .light: textMode = .custom1; custom1PromptID = "light"
    case .list: textMode = .custom2; custom2PromptID = "list"
    case .polish: textMode = .custom1; custom1PromptID = "polish"
    default: break
    }
    shortcutVersion = 3
  }

  private mutating func migratePromptCatalog(preserveImplicitBindings: Bool) {
    guard (promptCatalogVersion ?? 0) < 1 else { return }
    if preserveImplicitBindings {
      custom1PromptID = custom1PromptID ?? "polish"
      custom2PromptID = custom2PromptID ?? "instruction"
    }
    let replacements = ["light": "cleanup", "polish": "rewrite", "instruction": "agent", "list": "outline", "summary": "digest"]
    var retained: [TextPrompt] = []
    for prompt in promptLibrary ?? (preserveImplicitBindings ? TextPrompt.legacyDefaults : []) {
      let old = TextPrompt.legacyDefaults.first { $0.id == prompt.id }
      let legacyMode = TextMode(rawValue: prompt.id)
      let untouched = old == prompt || (old?.name == prompt.name && old?.englishName == prompt.englishName
        && legacyMode.map { TextPrompts().systemPrompt(for: $0) == prompt.instructions } == true)
      if untouched, let replacement = replacements[prompt.id] {
        if custom1PromptID == prompt.id { custom1PromptID = replacement }
        if custom2PromptID == prompt.id { custom2PromptID = replacement }
      } else {
        retained.append(prompt)
      }
    }
    // User-edited presets keep their original IDs and bindings. New presets
    // use separate IDs so they remain available without overwriting any edits.
    promptLibrary = TextPrompt.defaults.filter { preset in !retained.contains { $0.id == preset.id } } + retained
    promptCatalogVersion = 1
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
