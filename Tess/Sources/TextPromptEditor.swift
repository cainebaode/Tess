import SwiftUI

struct TextPromptEditor: View {
    var app: AppModel
    @State var prompts: [TextPrompt]
    @State var selectedID = ""
    @State private var editingInstructions = false
    @Environment(\.dismiss) private var dismiss

    private var selectedIndex: Int? { prompts.firstIndex { $0.id == selectedID } }
    private var preset: TextPrompt? { TextPrompt.defaults.first { $0.id == selectedID } }
    private var boundModes: [TextMode] {
        [TextMode.custom1, .custom2].filter { app.preferences.prompt(for: $0)?.id == selectedID }
    }
    private var chinese: Bool { app.preferences.language.usesChinese }
    private var canSave: Bool { !prompts.isEmpty && prompts.allSatisfy(\.isValid) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.tr("提示词库", "Prompt library")).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(app.tr("选择模板，再按自己的习惯调整", "Start with a template and make it yours"))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary)
            }.padding(22)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            promptGroup(app.tr("默认模板", "TEMPLATES"), values: prompts.filter { $0.guide != nil })
                            promptGroup(app.tr("我的提示词", "MY PROMPTS"), values: prompts.filter { $0.guide == nil })
                        }.padding(10)
                    }
                    Rectangle().fill(SettingsTheme.border).frame(height: 0.5)
                    HStack {
                        Button { addPrompt() } label: { Label(app.tr("新建", "New"), systemImage: "plus") }
                            .buttonStyle(.borderless)
                        Spacer()
                        Menu {
                            Button(app.tr("复制当前提示词", "Duplicate selected prompt")) {
                                if let index = selectedIndex {
                                    let original = prompts[index]
                                    let copy = TextPrompt(name: original.title(chinese: chinese) + app.tr(" 副本", " copy"), instructions: original.instructions)
                                    prompts.append(copy)
                                    selectedID = copy.id
                                }
                            }.disabled(selectedIndex == nil)
                            Menu(app.tr("添加默认模板", "Add a built-in template")) {
                                ForEach(TextPrompt.defaults) { value in
                                    Button(value.title(chinese: chinese)) {
                                        prompts.append(value)
                                        selectedID = value.id
                                    }.disabled(prompts.contains { $0.id == value.id })
                                }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 20, height: 24) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel(app.tr("提示词选项", "Prompt options"))
                    }.padding(14)
                }.frame(width: 200)
                    .background(SettingsSidebarBackdrop())
                if let index = selectedIndex {
                    promptDetail(index).id(selectedID)
                } else {
                    Spacer()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                LocalStorageNotice(app: app)
                if let invalid = prompts.first(where: { !$0.isValid }) {
                    Text(app.tr("请补全提示词的名称和内容：", "Add a name and instructions for: ") + invalid.title(chinese: chinese))
                        .font(.caption).foregroundStyle(SettingsTheme.warning)
                }
                HStack(spacing: 12) {
                    Text(app.tr("保存后，下次输入生效。", "Changes apply to your next input."))
                        .font(.caption).foregroundStyle(SettingsTheme.secondary)
                    Spacer()
                    Button(app.tr("取消", "Cancel")) { dismiss() }
                        .buttonStyle(.bordered).keyboardShortcut(.cancelAction)
                    Button {
                        if app.savePromptLibrary(prompts) { dismiss() }
                    } label: {
                        Text(app.tr("保存", "Save")).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 8)
                            .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).opacity(canSave ? 1 : 0.45)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!canSave)
                }
            }.padding(18)
        }
        .frame(width: 800, height: 620)
        .background(SettingsWindowBackdrop().ignoresSafeArea()).foregroundStyle(SettingsTheme.foreground)
        .tint(SettingsTheme.accent).preferredColorScheme(.light)
        .onAppear {
            if selectedIndex == nil { selectedID = prompts.first?.id ?? "" }
            editingInstructions = preset == nil
        }
        .onChange(of: selectedID) { _, _ in editingInstructions = preset == nil }
    }

    @ViewBuilder private func promptGroup(_ title: String, values: [TextPrompt]) -> some View {
        if !values.isEmpty {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(SettingsTheme.muted)
                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 5)
            ForEach(values) { prompt in
                Button { selectedID = prompt.id } label: {
                    HStack(spacing: 6) {
                        Text(prompt.title(chinese: chinese)).font(.system(size: 13, weight: .medium))
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        if [TextMode.custom1, .custom2].contains(where: { app.preferences.prompt(for: $0)?.id == prompt.id }) {
                            Image(systemName: "link").font(.caption).foregroundStyle(SettingsTheme.secondary)
                        }
                    }
                }.buttonStyle(SettingsNavigationStyle(isSelected: selectedID == prompt.id))
                    .accessibilityValue(selectedID == prompt.id ? app.tr("已选中", "Selected") : "")
            }
        }
    }

    private func promptDetail(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(app.tr("提示词名称", "Prompt name"), text: Binding(
                get: { prompts[index].title(chinese: chinese) },
                set: {
                    guard $0 != prompts[index].title(chinese: chinese) else { return }
                    prompts[index].name = $0
                    prompts[index].englishName = nil
                }
            )).textFieldStyle(.roundedBorder).font(.system(size: 15, weight: .semibold))
                .accessibilityLabel(app.tr("提示词名称", "Prompt name"))
            if let guide = prompts[index].guide {
                Text(chinese ? guide.zh : guide.en).font(.caption).foregroundStyle(SettingsTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(app.tr("查看内容", "Content"), selection: $editingInstructions) {
                    Text(app.tr("使用示例", "Example")).tag(false)
                    Text(app.tr("编辑提示词", "Edit prompt")).tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
            if editingInstructions {
                TextEditor(text: $prompts[index].instructions)
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .padding(10).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.border, lineWidth: 1) }
                    .accessibilityLabel(app.tr("提示词内容", "Prompt instructions"))
            } else if let guide = prompts[index].guide {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        example(app.tr("口述", "YOU SAY"), text: guide.input, secondary: true)
                        example(app.tr("整理后", "RESULT"), text: guide.output, secondary: false)
                        Text(app.tr("这是示意，实际结果取决于所选文字模型和提示词。", "Illustrative example. Actual results depend on your text model and prompt."))
                            .font(.caption).foregroundStyle(SettingsTheme.muted)
                        if let preset, prompts[index] != preset {
                            Text(app.tr("此模板已修改，示例仍展示默认版本。", "This template has edits; the example shows the default version."))
                                .font(.caption).foregroundStyle(SettingsTheme.warning)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }
            HStack {
                if let preset {
                    Button(app.tr("恢复默认", "Restore default")) { prompts[index] = preset }
                        .disabled(prompts[index] == preset)
                }
                Spacer()
                Button(app.tr("删除提示词", "Delete prompt")) {
                    prompts.remove(at: index)
                    selectedID = prompts.first?.id ?? ""
                }.disabled(!boundModes.isEmpty || prompts.count <= 1)
                    .help(app.tr("已绑定的提示词需先更换绑定才能删除。", "Rebind shortcuts before deleting a prompt in use."))
            }.buttonStyle(.borderless).font(.caption)
            Text(boundModes.isEmpty
                 ? app.tr("在快捷键设置中选择这条提示词即可使用。", "Select this prompt in Shortcuts to use it.")
                 : app.tr("正在用于：", "Used by: ") + boundModes.map { app.tr($0.title, $0.englishTitle) }.joined(separator: "、"))
                .font(.caption).foregroundStyle(SettingsTheme.secondary)
        }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func example(_ title: String, text: String, secondary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(SettingsTheme.muted)
            Text(text).font(.system(size: 13)).lineSpacing(4)
                .foregroundStyle(secondary ? SettingsTheme.secondary : SettingsTheme.foreground)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 9))
    }

    private func addPrompt() {
        let prompt = TextPrompt(name: app.tr("我的提示词", "My prompt"), instructions: "")
        prompts.append(prompt)
        selectedID = prompt.id
    }
}
