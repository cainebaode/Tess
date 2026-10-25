import SwiftUI

struct TextPromptEditor: View {
    var app: AppModel
    @State var prompts: TextPrompts
    @Environment(\.dismiss) private var dismiss
    private let defaults = TextPrompts()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(app.tr("整理提示词", "Editing prompts")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(app.tr("取消", "Cancel")) { dismiss() }.buttonStyle(SettingsButtonStyle())
            }.padding(20)
            Divider().overlay(SettingsTheme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(app.tr("实际发送的提示词 = 通用要求 + 当前模式规则。保存后对所有文字服务生效，从下一次整理开始使用。",
                                "The prompt sent is the common instructions plus the selected mode's rules. Saved changes apply to all text services starting with the next editing session."))
                        .font(.caption).foregroundStyle(SettingsTheme.secondary)
                    editor(app.tr("通用要求", "Common instructions"), text: $prompts.common, defaultText: defaults.common, height: 150)
                    editor(app.modeTitle(.light), text: $prompts.light, defaultText: defaults.light)
                    editor(app.modeTitle(.list), text: $prompts.list, defaultText: defaults.list)
                    editor(app.modeTitle(.polish), text: $prompts.polish, defaultText: defaults.polish)
                }.padding(22)
            }
            Divider().overlay(SettingsTheme.border)
            VStack(alignment: .leading, spacing: 10) {
                LocalStorageNotice(app: app)
                Text(app.tr("保存后，在文字服务的「编辑 / 测试」中选择模式，试用你的提示词。数字、术语等内容的保真检查仍然生效。",
                            "After saving, choose a mode in a text service's Edit / test panel to try your prompts. Checks for changes to numbers and terminology still apply."))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary)
                if !hasValidPrompts {
                    Text(app.tr("每种模式至少需要通用要求或模式规则，不能同时为空。", "Each mode needs common instructions or its own rules; both cannot be empty."))
                        .font(.caption).foregroundStyle(SettingsTheme.warning)
                }
                HStack {
                    Button(app.tr("全部恢复默认", "Restore all defaults")) { prompts = defaults }
                        .buttonStyle(SettingsButtonStyle())
                    Spacer()
                    Button(app.tr("保存提示词", "Save prompts")) {
                        if app.saveTextPrompts(prompts) { dismiss() }
                    }.buttonStyle(.borderedProminent).foregroundStyle(.white).disabled(!hasValidPrompts)
                }
            }.padding(18)
        }
        .frame(width: 680, height: 680)
        .background(SettingsTheme.background).foregroundStyle(SettingsTheme.foreground)
        .tint(SettingsTheme.accent).preferredColorScheme(.light)
    }

    private var hasValidPrompts: Bool {
        [TextMode.light, .list, .polish].allSatisfy {
            !prompts.systemPrompt(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func editor(_ title: String, text: Binding<String>, defaultText: String, height: CGFloat = 95) -> some View {
        SettingsCard(title: title) {
            TextEditor(text: text)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(8).frame(height: height)
                .background(SettingsTheme.sidebar, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(title).padding(.top, 10)
            HStack {
                Spacer()
                Button(app.tr("恢复默认", "Restore default")) { text.wrappedValue = defaultText }
                    .buttonStyle(SettingsButtonStyle()).disabled(text.wrappedValue == defaultText)
            }.padding(.vertical, 8)
        }
    }
}
