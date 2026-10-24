import SwiftUI

struct APIConfigEditor: View {
    var app: AppModel
    @State var configuration: APIConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var removeKey = false
    @State private var error: String?
    @State private var testResult: TextResult?
    @State private var sampleIndex = 0
    @State private var testTask: Task<Void, Never>?
    @State private var testing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(app.tr("文字模型配置", "Text model configuration")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(app.tr("关闭", "Close")) { dismiss() }.buttonStyle(SettingsButtonStyle())
            }.padding(20)
            Divider().overlay(SettingsTheme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard(title: app.tr("连接配置", "CONNECTION")) {
                        SettingsRow(title: app.tr("服务商预设", "Provider preset")) {
                            Picker(app.tr("服务商预设", "Provider preset"), selection: Binding(get: { configuration.presetID }, set: applyPreset)) {
                                ForEach(APIPreset.all) { preset in Text(preset.name).tag(preset.id) }
                            }.labelsHidden().frame(width: 250)
                        }
                        if let preset = APIPreset.all.first(where: { $0.id == configuration.presetID }) {
                            Text(preset.help).font(.caption).foregroundStyle(SettingsTheme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                            if let url = URL(string: preset.documentation), !preset.documentation.isEmpty {
                                Link(app.tr("官方配置说明", "Official setup guide"), destination: url)
                                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
                            }
                            if preset.id == "glm-free" {
                                Link(app.tr("登录智谱创建 API Key", "Create your API key at Zhipu"), destination: URL(string: "https://open.bigmodel.cn/console")!)
                                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 10)
                            }
                        }
                        field(app.tr("配置名称", "Configuration name"), value: $configuration.name)
                        SettingsRow(title: app.tr("接口协议", "API protocol")) {
                            Picker(app.tr("接口协议", "API protocol"), selection: $configuration.protocolKind) {
                                ForEach(APIProtocol.allCases, id: \.self) { protocolKind in Text(protocolKind.title).tag(protocolKind) }
                            }.labelsHidden().frame(width: 250)
                        }
                        field(app.tr("接口根地址", "Base URL"), value: $configuration.baseURL)
                        field("Model ID", value: $configuration.modelID)
                        if configuration.protocolKind == .anthropic {
                            field(app.tr("Workspace ID（可选）", "Workspace ID (optional)"), value: $configuration.workspaceID)
                        }
                        SettingsRow(title: "API Key", description: configuration.hasStoredKey
                                    ? app.tr("已有密钥；留空保留。改变接收域名后须重新填写。", "A credential is stored; leave blank to keep it. Enter it again after changing the receiving domain.")
                                    : app.tr("仅存入 Keychain，不写入普通配置。", "Stored only in Keychain, never in plain configuration.")) {
                            SecureField(app.tr("输入新密钥", "Enter new credential"), text: $apiKey).textFieldStyle(.roundedBorder).frame(width: 250)
                                .accessibilityLabel("API Key")
                        }
                        if configuration.hasStoredKey {
                            Toggle(app.tr("保存时移除已有密钥", "Remove stored credential on save"), isOn: $removeKey)
                                .font(.caption).padding(.vertical, 10)
                        }
                        if configuration.isLocal {
                            Toggle(app.tr("本机服务不需要 API Key", "Local service does not require an API key"), isOn: $configuration.allowsUnauthenticatedLocal)
                                .font(.caption).padding(.vertical, 10)
                        }
                        Text("\(app.tr("实际文字接收方", "Text recipient"))：\(configuration.receiver)")
                            .font(.caption).foregroundStyle(SettingsTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }.disabled(testing)
                    SettingsCard(title: app.tr("实际连接与样例测试", "REAL CONNECTION & SAMPLE TEST")) {
                        Text(app.tr("测试会将下方明确标记的样例发往当前配置，可能产生 API 费用。不会存入你的最近结果。连接通过与表达质量分开判断。",
                                    "Testing sends the labeled sample below to this configuration and may incur API charges. It is never saved as your recent result. Review connection status and wording quality separately."))
                            .font(.caption).foregroundStyle(SettingsTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                        Picker(app.tr("测试样例", "Test sample"), selection: $sampleIndex) {
                            ForEach(TextService.samples.indices, id: \.self) { index in
                                Text("\(app.tr("样例", "Sample")) \(index + 1)").tag(index)
                            }
                        }.padding(.vertical, 8).disabled(testing)
                        Text(TextService.samples[sampleIndex]).font(.system(size: 13)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(SettingsTheme.sidebar, in: RoundedRectangle(cornerRadius: 8))
                        HStack {
                            Button(app.tr("保存并测试轻量整理", "Save & test light editing")) { runTest() }
                                .disabled(testing).buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.regular)
                            if testing {
                                ProgressView().controlSize(.small)
                                Button(app.tr("取消测试", "Cancel test")) { testTask?.cancel() }.buttonStyle(SettingsButtonStyle())
                            }
                        }.padding(.vertical, 12)
                        if let result = testResult { resultView(result) }
                    }
                }.padding(22)
            }
            Divider().overlay(SettingsTheme.border)
            VStack(alignment: .leading, spacing: 10) {
                LocalStorageNotice(app: app)
                if let error { Text(error).font(.caption).foregroundStyle(SettingsTheme.warning).fixedSize(horizontal: false, vertical: true) }
                if !hasVerifiedConfiguration {
                    Text(app.tr("启用整理前，请向下滚动完成样例测试；保存配置不会自动启用整理。", "Before enabling editing, scroll down and test a sample. Saving a configuration does not enable editing."))
                        .font(.caption).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(app.tr("保存", "Save")) { if save() != nil { dismiss() } }
                    Spacer()
                    Button(app.tr("保存并设为当前", "Save & set current")) { useConfiguration(enableLightEditing: false) }
                    if hasVerifiedConfiguration {
                        Button(app.tr("使用并启用轻量整理", "Use & enable light editing")) { useConfiguration(enableLightEditing: true) }
                            .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.regular)
                    }
                }.disabled(testing).buttonStyle(SettingsButtonStyle())
            }.padding(18)
        }
        .frame(width: 680, height: 680)
        .background(SettingsTheme.background).foregroundStyle(SettingsTheme.foreground)
        .tint(SettingsTheme.accent).preferredColorScheme(.light)
        .onDisappear { testTask?.cancel(); apiKey = "" }
        .onChange(of: connectionIdentity) { _, _ in if !testing { testResult = nil } }
        .onChange(of: sampleIndex) { _, _ in testResult = nil }
    }

    private func field(_ title: String, value: Binding<String>) -> some View {
        SettingsRow(title: title) { TextField(title, text: value).textFieldStyle(.roundedBorder).frame(width: 300) }
    }

    private func applyPreset(_ id: String) {
        guard let preset = APIPreset.all.first(where: { $0.id == id }) else { return }
        configuration.presetID = preset.id
        configuration.protocolKind = preset.protocolKind
        configuration.baseURL = preset.baseURL
        configuration.allowsUnauthenticatedLocal = preset.id == "ollama"
        configuration.modelID = preset.defaultModelID
        if configuration.name.isEmpty || APIPreset.all.contains(where: { $0.name == configuration.name }) {
            configuration.name = preset.name
        }
        apiKey = ""
        testResult = nil
    }

    private func save() -> APIConfiguration? {
        let key: String? = removeKey ? "" : (apiKey.isEmpty ? nil : apiKey)
        guard app.configurations.save(configuration, apiKey: key),
              let snapshot = app.configurations.configurations.first(where: { $0.id == configuration.id }) else {
            error = app.configurations.lastError
            return nil
        }
        configuration = snapshot
        app.savePreferences()
        apiKey = ""
        removeKey = false
        error = nil
        return snapshot
    }

    private func runTest() {
        guard !testing, let snapshot = save() else { return }
        let sample = TextService.samples[sampleIndex]
        let key: String?
        do { key = try app.configurations.apiKey(for: snapshot) }
        catch { self.error = error.localizedDescription; return }
        testing = true
        testResult = nil
        testTask = Task { @MainActor in
            let result = await app.textService.process(sample, mode: .light, configuration: snapshot, apiKey: key)
            testing = false
            guard !Task.isCancelled else { return }
            testResult = result
            if app.configurations.markTested(snapshot, result: result),
               let tested = app.configurations.configurations.first(where: { $0.id == snapshot.id }) {
                configuration = tested
            } else {
                error = app.configurations.lastError ?? app.tr("测试结果未能保存，请重新测试后启用。", "The test result could not be saved. Test again before enabling editing.")
            }
        }
    }

    private var connectionIdentity: [String] {
        [configuration.protocolKind.rawValue, configuration.baseURL, configuration.modelID,
         configuration.workspaceID, String(configuration.allowsUnauthenticatedLocal), apiKey, String(removeKey)]
    }

    private var hasVerifiedConfiguration: Bool {
        guard error == nil, testResult?.error == nil, apiKey.isEmpty, !removeKey,
              let saved = app.configurations.configurations.first(where: { $0.id == configuration.id }),
              saved.testStatus == .passed else { return false }
        return configuration.protocolKind == saved.protocolKind && configuration.baseURL == saved.baseURL
            && configuration.modelID == saved.modelID && configuration.workspaceID == saved.workspaceID
            && configuration.allowsUnauthenticatedLocal == saved.allowsUnauthenticatedLocal
    }

    private func useConfiguration(enableLightEditing: Bool) {
        guard let snapshot = save() else { return }
        guard !enableLightEditing || snapshot.testStatus == .passed else {
            error = app.tr("配置有变更，请先重新测试。", "The configuration changed. Test it again first.")
            return
        }
        guard app.configurations.setCurrent(snapshot.id) else { error = app.configurations.lastError; return }
        if enableLightEditing { app.preferences.textMode = .light }
        app.savePreferences()
        dismiss()
    }

    private func resultView(_ result: TextResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let failure = result.error {
                Text(failure.message).foregroundStyle(SettingsTheme.warning)
            } else {
                Text(app.tr("已收到实际响应，请对照样例检查。", "A real response was received; compare it with the sample."))
                    .foregroundStyle(SettingsTheme.accent)
            }
            Text(result.candidate ?? result.output).font(.system(size: 13)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(SettingsTheme.sidebar, in: RoundedRectangle(cornerRadius: 8))
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).foregroundStyle(SettingsTheme.warning) }
            Text("\(app.tr("耗时", "Elapsed")) \(result.elapsed, specifier: "%.2f") s · \(result.modelID ?? configuration.modelID)")
                .foregroundStyle(SettingsTheme.secondary)
            if let usage = result.usage {
                Text("\(app.tr("服务返回用量", "Reported usage")) · input \(usage.input.map(String.init) ?? "—") · output \(usage.output.map(String.init) ?? "—") · total \(usage.total.map(String.init) ?? "—")")
                    .foregroundStyle(SettingsTheme.secondary)
            } else {
                Text(app.tr("服务未返回用量；不估算费用。", "The service did not report usage; no cost is estimated."))
                    .foregroundStyle(SettingsTheme.secondary)
            }
        }.font(.caption).padding(.vertical, 10)
    }
}
