import AppKit
import AVFoundation
import CoreAudio
import SwiftUI

struct SettingsView: View {
    var app: AppModel
    private var section: SettingsSection { app.settingsSection }
    @State private var editingConfiguration: APIConfiguration?
    @State private var deleteConfiguration: APIConfiguration?
    @State private var modelError: String?
    @State private var shortcutError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                TessAvatar(size: 30)
                TessWordmark(size: 27)
                Text("苔丝").font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsTheme.secondary)
                Spacer()
                Text(app.tr("设置", "Settings")).foregroundStyle(SettingsTheme.secondary)
            }
            .padding(.horizontal, 24).frame(height: 56)
            Divider().overlay(SettingsTheme.border)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SettingsSection.allCases) { value in
                        Button { app.settingsSection = value } label: {
                            Label(app.tr(value.zh, value.en), systemImage: value.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(section == value ? SettingsTheme.foreground : SettingsTheme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(section == value ? SettingsTheme.leaf.opacity(0.28) : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                                .overlay(alignment: .leading) {
                                    if section == value {
                                        Capsule().fill(SettingsTheme.accent).frame(width: 2).padding(.vertical, 8)
                                    }
                                }
                        }.buttonStyle(.plain)
                            .accessibilityValue(section == value ? app.tr("已选中", "Selected") : "")
                    }
                    Spacer()
                    Text("Tess \(appVersion)").font(.caption).foregroundStyle(SettingsTheme.secondary).padding(12)
                }
                .padding(12).frame(width: 190).frame(maxHeight: .infinity)
                .background(SettingsTheme.sidebar)
                Divider().overlay(SettingsTheme.border)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(app.tr(section.zh, section.en)).font(.system(size: 23, weight: .semibold))
                        LocalStorageNotice(app: app)
                        switch section {
                        case .general: general
                        case .speech: speech
                        case .text: textConfigurations
                        case .privacy: privacy
                        case .about: about
                        }
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 830, minHeight: 610)
        .background(SettingsTheme.background)
        .foregroundStyle(SettingsTheme.foreground)
        .tint(SettingsTheme.accent).preferredColorScheme(.light)
        .sheet(item: $editingConfiguration) { configuration in
            APIConfigEditor(app: app, configuration: configuration)
        }
        .alert(app.tr("删除文字配置？", "Delete this configuration?"), isPresented: Binding(
            get: { deleteConfiguration != nil }, set: { if !$0 { deleteConfiguration = nil } }
        )) {
            Button(app.tr("删除", "Delete"), role: .destructive) {
                if let value = deleteConfiguration, app.configurations.delete(value.id), app.configurations.current == nil {
                    app.preferences.textMode = .raw
                    app.savePreferences()
                }
                deleteConfiguration = nil
            }
            Button(app.tr("取消", "Cancel"), role: .cancel) { deleteConfiguration = nil }
        } message: {
            Text(app.tr("这会删除该配置及其 Keychain 密钥。", "This removes the configuration and its Keychain credential."))
        }
    }

    private var general: some View {
        VStack(spacing: 18) {
            SettingsCard(title: app.tr("输入准备", "READY TO USE")) {
                SettingsRow(title: app.tr("语音模型", "Speech model"),
                            description: app.asr.isReady(app.asr.selectedModel)
                            ? app.asr.selectedModel.title
                            : app.tr("先下载一个本地模型，即可开始听写。", "Download a local model to start dictation.")) {
                    Button(app.tr("选择与下载", "Choose & download")) { app.settingsSection = .speech }
                        .buttonStyle(SettingsButtonStyle())
                }
                SettingsRow(title: app.tr("文字整理（可选）", "Text editing (optional)"),
                            description: app.configurations.current?.name ?? app.tr("未配置时仍能听写原文和截图。", "Dictate the original transcript and capture screenshots without it.")) {
                    Button(app.tr("配置与测试", "Configure & test")) { app.settingsSection = .text }
                        .buttonStyle(SettingsButtonStyle())
                }
            }
            SettingsCard(title: app.tr("日常使用", "GENERAL")) {
                SettingsRow(title: app.tr("界面语言", "Interface language")) {
                    Picker("", selection: preference(\.language)) {
                        Text(app.tr("跟随系统", "System")).tag(InterfaceLanguage.system)
                        Text("简体中文").tag(InterfaceLanguage.chinese)
                        Text("English").tag(InterfaceLanguage.english)
                    }.frame(width: 155)
                }
                SettingsRow(title: app.tr("录音方式", "Recording behavior"), description: !app.preferences.holdToRecord
                            ? app.tr("按一次开始、再按一次结束；加载时再次按键可取消。", "Press once to start and again to finish; press again while loading to cancel.")
                            : app.preferences.bindings[.record]?.isFn == true
                            ? app.tr("按住 Fn 说话、松开结束；轻点 Fn 保持录音，再点结束。加载时也可轻点。", "Hold Fn and release to finish, or tap to keep recording and tap again to finish. Tapping also works while loading.")
                            : app.tr("按住说话，松开结束；加载期间松开会取消。", "Hold to speak and release to finish. Releasing while loading cancels.")) {
                    Picker("", selection: preference(\.holdToRecord)) {
                        Text(app.preferences.bindings[.record]?.isFn == true ? app.tr("按住 / 轻点", "Hold / tap") : app.tr("按住说话", "Hold to talk")).tag(true)
                        Text(app.tr("按键切换", "Press to toggle")).tag(false)
                    }.frame(width: 155).disabled(app.busy)
                }
                SettingsRow(title: app.tr("默认整理模式", "Default text mode"),
                            description: app.tr("用于菜单录音、截图说明和手动整理；语音快捷键直接决定本次模式。", "Used for menu recording, screenshot notes and pasted text. Each voice shortcut selects its own mode.")) {
                    Picker("", selection: Binding(get: { app.preferences.textMode }, set: { mode in
                        guard mode == .raw || app.configurations.current?.testStatus == .passed else { return }
                        app.preferences.textMode = mode
                        app.savePreferences()
                    })) {
                        ForEach(TextMode.allCases, id: \.self) { mode in
                            Text(modeTitle(mode)).tag(mode).disabled(mode != .raw && app.configurations.current?.testStatus != .passed)
                        }
                    }.frame(width: 155)
                }
                SettingsRow(title: app.tr("所有结果先预览", "Always preview results"),
                            description: app.tr("关闭后，语音直接输入原位置；目标变化或无法识别时自动复制。", "Otherwise, dictation goes into the original field, or is copied if the target changes or cannot be identified.")) {
                    Toggle("", isOn: preference(\.alwaysPreview)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsCard(title: app.tr("快捷键", "SHORTCUTS")) {
                ForEach(ShortcutAction.allCases) { action in
                    SettingsRow(title: shortcutTitle(action)) {
                        HStack(spacing: 8) {
                            ShortcutRecorder(label: app.preferences.bindings[action]?.label ?? app.tr("未绑定", "Unbound"),
                                             prompt: action.recordMode != nil ? app.tr("Fn 或组合键 · Esc 取消", "Fn or shortcut · Esc cancels") : app.tr("按组合键 · Esc 取消", "Press shortcut · Esc cancels"),
                                             accessibilityTitle: shortcutTitle(action),
                                             isEnabled: !app.busy,
                                             allowsFn: action.recordMode != nil,
                                             onStart: { app.hotkeys.suspend() },
                                             onFinish: { app.hotkeys.register(app.preferences.bindings) },
                                             onBinding: {
                                                 shortcutError = app.setShortcut(action, binding: $0) ? nil : app.hotkeys.lastError
                                             })
                                .frame(width: 160, height: 31).allowsHitTesting(!app.busy)
                            Button(app.tr("清除", "Clear")) {
                                shortcutError = app.setShortcut(action, binding: nil) ? nil : app.hotkeys.lastError
                            }
                                .buttonStyle(SettingsButtonStyle())
                            Button(app.tr("默认", "Default")) {
                                shortcutError = app.setShortcut(action, binding: action.defaults) ? nil : app.hotkeys.lastError
                            }
                                .buttonStyle(SettingsButtonStyle())
                        }.disabled(app.busy)
                    }
                }
                if app.preferences.bindings.values.contains(where: \.isFn) {
                    SettingsRow(title: app.tr("Fn 按键", "Fn key"), description: app.hotkeys.fnEnabled
                                ? app.tr("已启用。若弹出表情、切换输入法或系统听写，请在键盘设置里将 Fn 单独按键动作设为“不执行操作”。", "Enabled. If Fn opens emoji, switches input sources or invokes system dictation, set its standalone action to Do Nothing in Keyboard settings.")
                                : app.tr("需允许 Tess 的辅助功能权限。授权后返回此窗口即可启用，也可录入组合键。", "Allow Tess in Accessibility, then return here to enable Fn. A key combination is also available.")) {
                        if !app.hotkeys.fnEnabled {
                            Button(app.tr("启用 Fn", "Enable Fn")) {
                                app.delivery.requestAccessibilityPermission()
                                app.hotkeys.refreshFn()
                            }.buttonStyle(SettingsButtonStyle())
                        }
                        Button(app.tr("键盘设置", "Keyboard settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
                        }.buttonStyle(SettingsButtonStyle())
                    }
                }
                if let error = shortcutError ?? app.hotkeys.lastError { notice(error, isError: true) }
                notice(app.tr("每种语音模式都有独立快捷键，点击键位即可修改。Fn 组合建议先按修饰键再按 Fn；松开 Fn 结束，也可轻点保持录音、再点结束。Esc 取消当前操作或退出键位录入。",
                              "Each voice mode has its own shortcut. Click a binding to change it. For Fn combinations, press the modifier first, then Fn. Release Fn to finish, or tap to keep recording and tap again to finish. Esc cancels the operation or binding capture."))
                Button(app.tr("打开最近结果 / 粘贴文字", "Open recent result / paste text")) { app.showResult() }
                    .buttonStyle(SettingsButtonStyle()).padding(.vertical, 10)
            }
            #if TESS_INTERNAL_CHECKS
            HUDPreviewCard(isEnglish: !app.preferences.language.usesChinese)
            #endif
        }
    }

    private var speech: some View {
        VStack(spacing: 18) {
            SettingsCard(title: app.tr("本地识别模型", "LOCAL RECOGNITION MODELS")) {
                notice(app.tr("基础模型随应用提供，其他模型可按需下载。音频只在本机处理。较大的模型需要更多存储和内存。",
                              "The basic model is included; additional models can be downloaded. Audio stays on this Mac. Larger models need more storage and memory."))
                ForEach(ASRModel.allCases) { model in
                    modelRow(model)
                }
                notice(app.tr("来源：Hugging Face。重试会保留已完整校验的文件，未完成的文件重新下载。",
                              "Source: Hugging Face. Retry keeps fully verified files and restarts incomplete files."))
                if let error = modelError ?? app.asr.lastError { notice(error, isError: true) }
            }
            SettingsCard(title: app.tr("语音输入", "VOICE INPUT")) {
                SettingsRow(title: app.tr("识别语言", "Recognition language")) {
                    Picker("", selection: preference(\.recognitionLanguage)) {
                        Text(app.tr("自动识别中英文", "Automatic Chinese / English")).tag("auto")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }.frame(width: 210)
                }
                SettingsRow(title: app.tr("麦克风", "Microphone")) {
                    Picker("", selection: Binding(get: { app.recorder.selectedDeviceID }, set: { app.recorder.selectedDeviceID = $0; app.savePreferences() })) {
                        Text(app.tr("系统默认", "System default")).tag(AudioDeviceID?.none)
                        ForEach(app.recorder.devices) { device in Text(device.name).tag(Optional(device.id)) }
                    }.frame(width: 210).disabled(app.busy)
                }
                Button(app.tr("刷新麦克风列表", "Refresh microphones")) { app.recorder.refreshDevices() }
                    .buttonStyle(SettingsButtonStyle()).padding(.vertical, 10)
            }
        }.onAppear { app.recorder.refreshDevices() }
    }

    private func modelRow(_ model: ASRModel) -> some View {
        let state = app.asr.states[model] ?? .notDownloaded
        let progress = app.asr.downloadProgress[model]
        let total = progress?.total
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title).font(.system(size: 13, weight: .medium))
                    Text(model.detail).font(.caption).foregroundStyle(SettingsTheme.secondary)
                    Text("\(total == nil ? app.tr("预计下载", "Estimated download") : app.tr("下载大小", "Download size")) \(bytes(total ?? model.estimatedBytes)) · \(app.tr("需可用空间", "Free space required")) \(bytes(total.map { ASRModel.requiredFreeBytes(for: $0) } ?? model.requiredFreeBytes))")
                        .font(.caption).foregroundStyle(SettingsTheme.secondary)
                }
                Spacer()
                if app.asr.selectedModel == model {
                    Label(app.tr("当前", "Current"), systemImage: "checkmark.circle.fill").foregroundStyle(SettingsTheme.accent)
                } else {
                    Button(app.tr("选择", "Select")) { app.asr.selectedModel = model; app.savePreferences() }
                        .buttonStyle(SettingsButtonStyle()).disabled(app.busy)
                }
            }
            HStack {
                Text(state.label)
                    .font(.caption).foregroundStyle(SettingsTheme.secondary)
                if app.asr.isReady(model) {
                    Text("· \(bytes(app.asr.diskUsage(model)))").font(.caption).foregroundStyle(SettingsTheme.secondary)
                }
                Spacer()
                if modelIsDownloading(model) {
                    if state != .connecting, state != .fetchingManifest, let fraction = progress?.fraction {
                        ProgressView(value: fraction).frame(width: 100)
                        Text(fraction, format: .percent.precision(.fractionLength(1)))
                            .font(.caption).monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small).frame(width: 16, height: 16)
                    }
                    Button(app.tr("取消", "Cancel")) { app.asr.cancelDownload(model) }.buttonStyle(SettingsButtonStyle())
                } else if app.asr.usesBundledModel(model) {
                    Text(app.tr("随应用提供", "Included with Tess")).font(.caption).foregroundStyle(SettingsTheme.secondary)
                } else if app.asr.isReady(model) {
                    Button(app.tr("删除模型", "Delete model")) {
                        do { try app.asr.delete(model); modelError = nil }
                        catch { modelError = error.localizedDescription }
                    }.buttonStyle(SettingsButtonStyle()).disabled(app.busy)
                } else {
                    Button {
                        app.asr.selectedModel = model
                        app.savePreferences()
                        Task { await app.asr.download(model) }
                    } label: {
                        if case .failed = state {
                            Text(app.tr("重试", "Retry"))
                        } else {
                            Text(app.asr.selectedModel == model ? app.tr("下载", "Download") : app.tr("下载并选择", "Download & select"))
                        }
                    }
                        .buttonStyle(SettingsButtonStyle()).disabled(app.busy)
                }
            }
            if modelIsDownloading(model), let progress, let total = progress.total {
                HStack(spacing: 10) {
                    Text("\(bytes(progress.received)) / \(bytes(total))").monospacedDigit().fixedSize()
                    if let fileName = progress.fileName {
                        Text(fileName).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(.caption).foregroundStyle(SettingsTheme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 13).overlay(alignment: .bottom) { Divider().overlay(SettingsTheme.foreground.opacity(0.08)) }
    }

    private var textConfigurations: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: app.tr("文字服务", "TEXT SERVICE")) {
                notice(app.tr("仅将待整理文字交给所选服务。截图和原始音频不会发往文字模型。API 与聊天会员分开计费。",
                              "Only the editing text is sent to the selected service. Screenshots and original audio are never sent to the text model. API billing is separate from chat subscriptions."))
                if app.configurations.configurations.isEmpty {
                    SettingsRow(title: app.tr("尚未配置", "No configuration"),
                                description: app.tr("仍可使用原文听写和截图。", "Dictation with the original transcript and screenshots remain available.")) { EmptyView() }
                }
                ForEach(app.configurations.configurations) { value in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(value.name).font(.system(size: 13, weight: .medium))
                                Text("\(value.receiver) · \(value.modelID)").font(.caption).foregroundStyle(SettingsTheme.secondary)
                                Text(testStatus(value)).font(.caption).foregroundStyle(value.testStatus == .passed ? SettingsTheme.accent : SettingsTheme.secondary)
                            }
                            Spacer()
                            if app.configurations.currentID == value.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(SettingsTheme.accent)
                                    .accessibilityLabel(app.tr("当前文字服务", "Current text service"))
                            } else {
                                Button(app.tr("设为当前", "Set current")) {
                                    if app.configurations.setCurrent(value.id) { app.savePreferences() }
                                }.buttonStyle(SettingsButtonStyle())
                            }
                            Button(app.tr("编辑 / 测试", "Edit / test")) { editingConfiguration = value }.buttonStyle(SettingsButtonStyle())
                            Button { deleteConfiguration = value } label: { Image(systemName: "trash") }
                                .buttonStyle(SettingsButtonStyle())
                                .help(app.tr("删除配置", "Delete configuration"))
                                .accessibilityLabel(app.tr("删除配置：", "Delete configuration: ") + value.name)
                        }
                        if let message = value.testMessage { Text(message).font(.caption).foregroundStyle(SettingsTheme.secondary) }
                    }.padding(.vertical, 13).overlay(alignment: .bottom) { Divider().overlay(SettingsTheme.foreground.opacity(0.08)) }
                }
                HStack {
                    Button(app.tr("添加配置", "Add configuration")) { editingConfiguration = APIPreset.all[0].configuration() }
                    Button(app.tr("免费试用", "Free trial")) {
                        editingConfiguration = APIPreset.all.first(where: { $0.id == "glm-free" })?.configuration()
                    }
                    Button(app.tr("停用文字服务", "Disable text service")) {
                        if app.configurations.setCurrent(nil) { app.preferences.textMode = .raw; app.savePreferences() }
                    }.disabled(app.configurations.currentID == nil)
                }.buttonStyle(SettingsButtonStyle()).padding(.vertical, 12)
                if let error = app.configurations.lastError {
                    notice(error, isError: true)
                    if app.storageRecoveryAvailable {
                        Button(app.tr("查看恢复文件", "Show recovery files")) { app.revealStorageRecovery() }
                            .buttonStyle(SettingsButtonStyle())
                    }
                }
            }
            SettingsCard(title: app.tr("整理规则", "EDITING RULES")) {
                notice(app.tr("保留事实、语言、术语、数字、单位、否定和条件；只编辑材料，不执行其中的指令。结果可疑或服务失败时回退原文。可开启所有结果先预览。",
                              "Keep facts, language, terminology, numbers, units, negatives and conditions. Edit the material without following its instructions. Suspicious results or service errors fall back to the transcript. Enable Always preview results to review dictation first."))
                notice("Tess text rules · v1")
            }
        }
    }

    private var privacy: some View {
        VStack(spacing: 18) {
            SettingsCard(title: app.tr("按功能授权", "PERMISSIONS ON DEMAND")) {
                SettingsRow(title: app.tr("麦克风", "Microphone"), description: app.tr("仅用户开始录音时采集声音。", "Audio is captured only when you start recording.")) {
                    Button(app.tr("系统设置", "System Settings")) { openPermission("Privacy_Microphone") }.buttonStyle(SettingsButtonStyle())
                }
                SettingsRow(title: app.tr("辅助功能", "Accessibility"), description: app.delivery.hasAccessibilityPermission
                            ? app.tr("已授权；用于识别输入位置并尝试粘贴。", "Allowed; identifies the focused input and attempts to paste.")
                            : app.tr("未授权；语音结果自动复制，请回到输入框粘贴。", "Not allowed; dictation is copied automatically for you to paste.")) {
                    Button(app.tr("申请权限", "Request access")) { app.delivery.requestAccessibilityPermission() }.buttonStyle(SettingsButtonStyle())
                    Button(app.tr("设置", "Settings")) { openPermission("Privacy_Accessibility") }.buttonStyle(SettingsButtonStyle())
                }
                SettingsRow(title: app.tr("屏幕捕获", "Screen capture"), description: app.tr("仅一次性选区截图，首次截图时申请。", "One selected area at a time; requested on first capture.")) {
                    Button(app.tr("系统设置", "System Settings")) { openPermission("Privacy_ScreenCapture") }.buttonStyle(SettingsButtonStyle())
                }
                notice(app.tr("仅识别快捷键和输入目标保护所需的事件，不读取或保存打字正文。不会申请全盘访问、通讯录或照片权限。",
                              "Tess only interprets events needed for shortcuts and input-target protection. Typed text is never read or stored. Tess does not request full disk, contacts or photo access."))
            }
            SettingsCard(title: app.tr("数据与清理", "DATA & CLEANUP")) {
                notice(app.tr("API 密钥仅保存在 Keychain。基础模型随应用提供，额外模型保存在 Tess 模型目录。最近结果与截图草稿最多保留 24 小时；清除暂存内容不会删除模型或 API 配置。",
                              "API credentials are stored only in Keychain. The basic model is included with Tess; downloaded models stay in its model directory. Recent results and screenshot drafts expire after 24 hours. Clearing temporary content keeps models and API configurations."))
                notice(app.tr("自动粘贴会短暂使用剪贴板并尽力恢复可恢复内容；仅当剪贴板没有被其他操作更改时恢复。显式复制会保留 Tess 内容。剪贴板管理器及通用剪贴板可能接触这些内容。",
                              "Pasting briefly uses the clipboard and restores recoverable content only if it has not changed. Explicit Copy keeps Tess content on the clipboard. Clipboard managers and Universal Clipboard may see it."))
                notice(app.tr("Tess 不建立账号、云中转或远程使用统计。第三方服务及目标应用的数据保留由对方决定。",
                              "Tess has no account, cloud relay or remote usage analytics. Third-party services and destination apps control their own data retention."))
                Button(app.tr("清除结果与截图草稿", "Clear result and screenshot draft")) { app.clearTemporaryContent() }
                    .buttonStyle(SettingsButtonStyle()).padding(.vertical, 12)
            }
        }
    }

    private var about: some View {
        SettingsCard(title: "TESS · \(appVersion)") {
            HStack(spacing: 20) {
                TessMascot(height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TessWordmark(size: 40)
                        Text("苔丝").font(.system(size: 15, weight: .medium)).foregroundStyle(SettingsTheme.secondary)
                    }
                    Text(app.tr("Mac 上的语音输入、截图说明与文字整理。Apple Silicon · macOS 26+。",
                                "Voice input, screenshot notes and text editing on Mac. Apple Silicon · macOS 26+."))
                        .font(.system(size: 13)).foregroundStyle(SettingsTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 18)
            Divider().overlay(SettingsTheme.foreground.opacity(0.08))
            SettingsRow(title: app.tr("使用帮助与更新", "Help & updates"), description: app.tr("查看快捷键、权限排查、隐私说明和安装更新方法。", "Shortcuts, permissions, privacy and installing updates.")) {
                Button(app.tr("打开帮助", "Open help")) {
                    if let url = Bundle.main.url(forResource: "Help", withExtension: "html") { NSWorkspace.shared.open(url) }
                }.buttonStyle(SettingsButtonStyle())
            }
            notice(app.tr("本地识别基于 speech-swift；Qwen3-ASR 与 Whisper 模型按各自许可使用。", "Local recognition uses speech-swift; Qwen3-ASR and Whisper models follow their respective licenses."))
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { app.preferences[keyPath: keyPath] }, set: { app.preferences[keyPath: keyPath] = $0; app.savePreferences() })
    }
    private func notice(_ text: String, isError: Bool = false) -> some View {
        Text(text).font(.caption).foregroundStyle(isError ? SettingsTheme.warning : SettingsTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.vertical, 9)
    }
    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
    private func modelIsDownloading(_ model: ASRModel) -> Bool {
        switch app.asr.states[model] {
        case .connecting, .fetchingManifest, .downloading, .verifying: true
        default: false
        }
    }
    private func openPermission(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
    private func shortcutTitle(_ action: ShortcutAction) -> String {
        switch action {
        case .record: app.tr("语音输入 · 原文", "Voice input · Original")
        case .recordLight: app.tr("语音输入 · 轻量整理", "Voice input · Light cleanup")
        case .recordList: app.tr("语音输入 · 列表整理", "Voice input · List")
        case .recordPolish: app.tr("语音输入 · 自然润色", "Voice input · Polish")
        case .screenshot: app.tr("选区截图", "Capture area")
        case .result: app.tr("最近结果", "Recent result")
        }
    }
    private func modeTitle(_ mode: TextMode) -> String {
        switch mode {
        case .raw: app.tr("原文", "Original")
        case .light: app.tr("轻量整理", "Light edit")
        case .list: app.tr("列表整理", "List")
        case .polish: app.tr("自然润色", "Polish")
        }
    }
    private func testStatus(_ configuration: APIConfiguration) -> String {
        switch configuration.testStatus {
        case .untested: app.tr("尚未测试", "Not tested")
        case .changed: app.tr("配置已变更，请重新测试", "Configuration changed; test again")
        case .failed: app.tr("测试失败", "Test failed")
        case .passed: app.tr("连接通过，表达质量需人工确认", "Connection passed; review wording manually")
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, speech, text, privacy, about
    var id: String { rawValue }
    var zh: String { switch self { case .general: "通用与快捷键"; case .speech: "语音识别"; case .text: "文字模型"; case .privacy: "权限与数据"; case .about: "关于" } }
    var en: String { switch self { case .general: "General & shortcuts"; case .speech: "Speech recognition"; case .text: "Text models"; case .privacy: "Permissions & data"; case .about: "About" } }
    var icon: String { switch self { case .general: "slider.horizontal.3"; case .speech: "waveform"; case .text: "text.alignleft"; case .privacy: "lock.shield"; case .about: "info.circle" } }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let prompt: String
    let accessibilityTitle: String
    let isEnabled: Bool
    let allowsFn: Bool
    let onStart: () -> Void
    let onFinish: () -> Void
    let onBinding: (ShortcutBinding) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderControl { ShortcutRecorderControl() }
    func updateNSView(_ view: ShortcutRecorderControl, context: Context) {
        view.label = label
        view.prompt = prompt
        view.enabled = isEnabled
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(accessibilityTitle)
        view.setAccessibilityValue(label)
        view.setAccessibilityHelp(prompt)
        view.setAccessibilityEnabled(isEnabled)
        view.allowsFn = allowsFn
        view.onStart = onStart
        view.onFinish = onFinish
        view.onBinding = onBinding
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view: ShortcutRecorderControl, coordinator: ()) { view.finish() }
}

private final class ShortcutRecorderControl: NSView {
    var label = ""
    var prompt = ""
    var allowsFn = false
    var enabled = true
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onBinding: ((ShortcutBinding) -> Void)?
    private var recording = false
    private var pendingFn: ShortcutBinding?
    override var acceptsFirstResponder: Bool { enabled }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        beginRecording()
        return true
    }
    private func beginRecording() {
        guard enabled, !recording else { return }
        window?.makeFirstResponder(self)
        recording = true
        onStart?()
        setAccessibilityValue(prompt)
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        guard enabled else { return }
        guard recording else {
            if [36, 49, 76].contains(event.keyCode) { beginRecording() }
            else { super.keyDown(with: event) }
            return
        }
        guard !event.isARepeat else { return }
        if event.keyCode != 53 { onBinding?(ShortcutBinding.from(event)) }
        finish()
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording, allowsFn else { super.flagsChanged(with: event); return }
        if event.keyCode == 63 {
            if event.modifierFlags.contains(.function) {
                pendingFn = ShortcutBinding(keyCode: 63, modifiers: ShortcutBinding.from(event).modifiers)
            } else if let pendingFn {
                onBinding?(pendingFn)
                finish()
            }
        } else if pendingFn != nil {
            let masks: [UInt16: NSEvent.ModifierFlags] = [54: .command, 55: .command, 56: .shift, 60: .shift, 58: .option, 61: .option, 59: .control, 62: .control]
            guard let mask = masks[event.keyCode] else { return }
            if event.modifierFlags.contains(mask) {
                pendingFn = ShortcutBinding(keyCode: 63, modifiers: ShortcutBinding.from(event).modifiers)
            } else if let pendingFn {
                onBinding?(pendingFn)
                finish()
            }
        }
    }
    override func resignFirstResponder() -> Bool { finish(); needsDisplay = true; return true }
    func finish() {
        guard recording else { return }
        recording = false
        pendingFn = nil
        setAccessibilityValue(label)
        onFinish?()
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        (recording ? SettingsTheme.accentColor.withAlphaComponent(0.16) : SettingsTheme.accentColor.withAlphaComponent(0.08)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        if window?.firstResponder === self {
            SettingsTheme.accentColor.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            focus.lineWidth = 2
            focus.stroke()
        }
        let text = recording ? prompt : label
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: SettingsTheme.foregroundColor, .paragraphStyle: paragraph]
        text.draw(in: NSRect(x: 4, y: (bounds.height - 14) / 2, width: bounds.width - 8, height: 15), withAttributes: attributes)
    }
}
