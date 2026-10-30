import SwiftUI

struct SpeechVocabularyView: View {
    var app: AppModel
    @State private var editingWord: SpeechWord?
    private var vocabulary: SpeechVocabulary { app.preferences.speechVocabulary ?? SpeechVocabulary() }

    var body: some View {
        VStack(spacing: 18) {
            SpeechLearningSettings(app: app)
            SettingsCard(title: app.tr("常用词", "PERSONAL VOCABULARY")) {
                Toggle(app.tr("使用常用词与场景提示", "Use vocabulary and scene hints"), isOn: Binding(
                    get: { vocabulary.enabled }, set: { value in
                        var next = vocabulary; next.enabled = value; _ = app.saveVocabulary(next)
                    }
                )).toggleStyle(.switch).padding(.vertical, 12)
                Text(app.tr("用于本地 Qwen 识别。词库初始为空；误写仅作校正候选，不会全局替换。录音开始后修改的内容下次生效。",
                            "Hints guide local Qwen recognition. Mistaken spellings are candidates, never global replacements. Changes take effect with the next recording."))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
                Text(app.tr("词汇提示可能改善术语，也可能影响其他字词；请按实际录音效果决定是否启用。",
                            "Vocabulary hints can improve terms and also affect other words. Enable them based on your recordings."))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
                if app.asr.selectedModel == .whisper {
                    Text(app.tr("Whisper 暂不使用词汇提示；下方的文字校正仍可使用。", "Whisper does not use vocabulary hints. Text correction below is still available."))
                        .font(.caption).foregroundStyle(SettingsTheme.warning)
                }
                TextField(app.tr("可选场景，例如：正在讨论产品需求（最多 240 字）", "Optional scene, e.g. discussing product requirements (240 characters)"), text: Binding(
                    get: { vocabulary.scene }, set: { value in
                        var next = vocabulary; next.scene = String(value.prefix(240)); _ = app.saveVocabulary(next)
                    }
                )).textFieldStyle(.roundedBorder).padding(.vertical, 10)
                ForEach(vocabulary.words) { word in
                    HStack(spacing: 10) {
                        Toggle(word.spelling, isOn: Binding(get: { word.enabled }, set: { enabled in
                            var next = word; next.enabled = enabled; _ = app.saveWord(next)
                        })).toggleStyle(.checkbox).frame(width: 130, alignment: .leading)
                        Text(word.meaning).font(.caption).foregroundStyle(SettingsTheme.secondary)
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Button(app.tr("编辑", "Edit")) { editingWord = word }
                            .buttonStyle(SettingsButtonStyle())
                        Button { var next = vocabulary; next.words.removeAll { $0.id == word.id }; _ = app.saveVocabulary(next) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless).help(app.tr("删除词条", "Delete word"))
                    }.padding(.vertical, 6)
                }
                HStack {
                    Button(app.tr("添加常用词…", "Add word…")) { editingWord = SpeechWord() }
                        .buttonStyle(SettingsButtonStyle()).disabled(vocabulary.words.count >= SpeechVocabulary.wordLimit)
                    Spacer()
                    Text("\(vocabulary.words.count) / \(SpeechVocabulary.wordLimit)").font(.caption).foregroundStyle(SettingsTheme.muted)
                }.padding(.vertical, 10)
                Text(app.tr("示例：PRD · 产品需求文档 · 常见误写 PLD、P R D。提示最多 2,000 字，优先使用列表前面的词条。",
                            "Example: PRD · Product requirements document · Mistaken spellings PLD, P R D. Hints use up to 2,000 characters, in list order."))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary).padding(.bottom, 8)
            }
            SettingsCard(title: app.tr("结束后的上下文校正", "CONTEXT CORRECTION AFTER RECORDING")) {
                Text(app.tr("默认关闭。开启后，转写文本、相关词条与场景会发送给你配置的文字服务；音频仍留在本机。校正与所选模板合并为一次请求，等待最多 8 秒，失败时使用原文。",
                            "Off by default. Sends the transcript, relevant words and scene to your text service; audio stays local. Correction and your template share one request, with an 8-second limit and original-text fallback."))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                ForEach(TextMode.allCases) { mode in
                    Toggle(mode == .raw ? app.tr("Fn 基础听写", "Fn dictation") : app.tr(mode.title, mode.englishTitle), isOn: Binding(
                        get: { app.preferences.correctsContext(for: mode) }, set: { enabled in
                            var modes = app.preferences.contextCorrectionModes ?? []
                            modes.removeAll { $0 == mode }
                            if enabled { modes.append(mode) }
                            app.preferences.contextCorrectionModes = modes; app.savePreferences()
                        }
                    )).toggleStyle(.switch).padding(.vertical, 5)
                }
                if app.configurations.current?.testStatus != .passed {
                    Button(app.tr("配置并测试文字服务", "Configure and test a text service")) { app.showSettings(.text) }
                        .buttonStyle(SettingsButtonStyle()).padding(.vertical, 10)
                }
            }
        }
        .sheet(item: $editingWord) { word in SpeechWordEditor(app: app, word: word) }
    }
}

struct SpeechWordEditor: View {
    var app: AppModel
    @State var word: SpeechWord
    @State private var aliases = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(app.tr("常用词", "Personal word")).font(.title2.weight(.semibold))
            TextField(app.tr("标准写法（例如 PRD）", "Standard spelling (e.g. PRD)"), text: $word.spelling)
            TextField(app.tr("释义或使用场景（可选）", "Meaning or context (optional)"), text: $word.meaning)
            TextField(app.tr("常见误写，用逗号分隔（可选）", "Mistaken spellings, comma-separated (optional)"), text: $aliases)
            Text(app.tr("保存前确认写法与释义。仅在你启用词库后使用；误写不是无条件替换规则。",
                        "Confirm the spelling and meaning. Used only when vocabulary is enabled; mistaken spellings are not unconditional replacement rules."))
                .font(.caption).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(SettingsTheme.warning) }
            HStack {
                Button(app.tr("取消", "Cancel")) { dismiss() }
                Spacer()
                Button(app.tr("保存", "Save")) {
                    word.spelling = word.spelling.trimmingCharacters(in: .whitespacesAndNewlines)
                    word.meaning = word.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                    word.aliases = aliases.components(separatedBy: CharacterSet(charactersIn: ",，、\n"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if app.saveWord(word) { dismiss() }
                    else { error = app.storageNotice ?? app.tr("写法需唯一且不超过 64 字，释义最多 160 字；最多 8 个误写，每个不超过 80 字。", "Use a unique spelling up to 64 characters, meaning up to 160, and up to 8 mistaken spellings of 80 characters each.") }
                }.buttonStyle(.borderedProminent)
            }.buttonStyle(SettingsButtonStyle())
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 500)
            .background(SettingsWindowBackdrop()).foregroundStyle(SettingsTheme.foreground)
            .onAppear { aliases = word.aliases.joined(separator: ", ") }
    }
}
