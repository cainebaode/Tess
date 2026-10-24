import Foundation
import Observation
import Security

enum APIProtocol: String, CaseIterable, Codable, Sendable {
    case openAI, anthropic

    var title: String { self == .openAI ? "OpenAI Chat Completions" : "Anthropic Messages" }
    var endpointPath: String { self == .openAI ? "chat/completions" : "messages" }
}

enum APITestStatus: String, Codable, Sendable {
    case untested, passed, failed, changed
}

struct APIConfiguration: Identifiable, Codable, Sendable {
    var id = UUID()
    var name = ""
    var presetID = "custom"
    var protocolKind: APIProtocol = .openAI
    var baseURL = ""
    var modelID = ""
    var workspaceID = ""
    var allowsUnauthenticatedLocal = false
    fileprivate(set) var credentialID: UUID?
    fileprivate(set) var credentialOrigin: String?
    fileprivate(set) var testStatus: APITestStatus = .untested
    fileprivate(set) var testedAt: Date?
    fileprivate(set) var testedModel: String?
    fileprivate(set) var testMessage: String?

    var endpoint: URL? { try? APIAddress(baseURL: baseURL, protocolKind: protocolKind).endpoint }
    var receiver: String { endpoint?.host() ?? "—" }
    var isLocal: Bool { endpoint.map { APIAddress.isLoopback($0.host() ?? "") } ?? false }
    var hasStoredKey: Bool { credentialID != nil }
    fileprivate var processingIdentity: String {
        [protocolKind.rawValue, baseURL, modelID, workspaceID, String(allowsUnauthenticatedLocal), credentialID?.uuidString ?? ""].joined(separator: "\n")
    }
}

struct APIPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let protocolKind: APIProtocol
    let baseURL: String
    let help: String
    let documentation: String
    var defaultModelID: String { id == "glm-free" ? "glm-4.7-flash" : "" }

    func configuration() -> APIConfiguration {
        var value = APIConfiguration()
        value.name = name
        value.presetID = id
        value.protocolKind = protocolKind
        value.baseURL = baseURL
        value.modelID = defaultModelID
        value.allowsUnauthenticatedLocal = id == "ollama"
        return value
    }

    // Addresses are examples, checked against official documentation on 2026-10-08.
    // The free trial preset supplies a model ID; every configuration still needs testing.
    static let all: [APIPreset] = [
        .init(id: "openai", name: "OpenAI", protocolKind: .openAI, baseURL: "https://api.openai.com/v1", help: "选择支持 Chat Completions 的文字模型。", documentation: "https://developers.openai.com/api/reference/chat/create"),
        .init(id: "anthropic", name: "Anthropic Claude", protocolKind: .anthropic, baseURL: "https://api.anthropic.com/v1", help: "使用 Claude API Key；多工作空间密钥需填写 Workspace ID。", documentation: "https://platform.claude.com/docs/en/api/overview"),
        .init(id: "gemini", name: "Google Gemini", protocolKind: .openAI, baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", help: "使用 Gemini API Key 与官方兼容接口。", documentation: "https://ai.google.dev/gemini-api/docs/openai"),
        .init(id: "deepseek", name: "DeepSeek", protocolKind: .openAI, baseURL: "https://api.deepseek.com", help: "选择 Chat Completions 文字模型；仅使用最终正文。", documentation: "https://api-docs.deepseek.com/guides/codex"),
        .init(id: "qwen", name: "阿里云百炼 Qwen", protocolKind: .openAI, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", help: "示例为北京地域。请按账户地域、业务空间与计费方案更改地址，配套使用 API Key。", documentation: "https://help.aliyun.com/en/model-studio/base-url"),
        .init(id: "doubao", name: "火山方舟 豆包", protocolKind: .openAI, baseURL: "https://ark.cn-beijing.volces.com/api/v3", help: "填写文字模型或推理接入点 ID；与豆包 ASR 凭据独立。", documentation: "https://docs.volcengine.com/docs/ark/compatible-with-openai-sdk?lang=zh"),
        .init(id: "kimi", name: "月之暗面 Kimi", protocolKind: .openAI, baseURL: "https://api.moonshot.cn/v1", help: "示例为国内 API；国际账户按控制台选择 api.moonshot.ai/v1。", documentation: "https://platform.kimi.com/docs/guide/migrating-from-openai-to-kimi"),
        .init(id: "glm", name: "智谱 GLM", protocolKind: .openAI, baseURL: "https://open.bigmodel.cn/api/paas/v4", help: "示例为通用 API，Coding 套餐与国际地域地址可能不同。", documentation: "https://docs.bigmodel.cn/cn/guide/develop/openai/introduction"),
        .init(id: "glm-free", name: "智谱 GLM-4.7-Flash · 免费试用", protocolKind: .openAI, baseURL: "https://open.bigmodel.cn/api/paas/v4", help: "此模型官方当前免费，仍需登录智谱创建自己的 API Key，并受服务限流约束。仅待整理文字发往智谱。更换模型或地址后请重新核对价格。", documentation: "https://docs.bigmodel.cn/cn/guide/models/free/glm-4.7-flash"),
        .init(id: "minimax", name: "MiniMax", protocolKind: .openAI, baseURL: "https://api.minimax.cn/v1", help: "按国内或国际账户核对地址；国际 API 示例为 https://api.minimax.io/v1。", documentation: "https://platform.minimax.cn/docs/api-reference/text-openai-api"),
        .init(id: "hunyuan", name: "腾讯混元", protocolKind: .openAI, baseURL: "https://api.hunyuan.cloud.tencent.com/v1", help: "此地址用于原混元平台 API Key；新购服务迁移至 TokenHub，请按控制台填写兼容地址。", documentation: "https://cloud.tencent.com/document/product/1729/111007"),
        .init(id: "qianfan", name: "百度千帆 文心", protocolKind: .openAI, baseURL: "https://qianfan.baidubce.com/v2", help: "使用 v2 API Key 与模型名，不使用旧 access_token。", documentation: "https://cloud.baidu.com/doc/qianfan-docs/s/Fm9l6ocai"),
        .init(id: "xai", name: "xAI Grok", protocolKind: .openAI, baseURL: "https://api.x.ai/v1", help: "选择支持 Chat Completions 的文字模型。", documentation: "https://docs.x.ai/developers/rest-api-reference/inference/chat-completions"),
        .init(id: "siliconflow", name: "硅基流动 · 聚合平台", protocolKind: .openAI, baseURL: "https://api.siliconflow.cn/v1", help: "文字发往硅基流动，由平台提供所选模型。", documentation: "https://docs.siliconflow.cn/docs/userguide/quickstart"),
        .init(id: "openrouter", name: "OpenRouter · 聚合平台", protocolKind: .openAI, baseURL: "https://openrouter.ai/api/v1", help: "文字发往 OpenRouter，由平台路由所选模型。", documentation: "https://openrouter.ai/docs/quickstart"),
        .init(id: "ollama", name: "Ollama · 本机", protocolKind: .openAI, baseURL: "http://127.0.0.1:11434/v1", help: "先自行安装模型并启动 Ollama；本机服务是否转发由服务本身决定。", documentation: "https://docs.ollama.com/api/openai-compatibility"),
        .init(id: "custom", name: "自定义兼容服务", protocolKind: .openAI, baseURL: "", help: "填写接口根地址，云端须 HTTPS；HTTP 仅允许本机回环地址。", documentation: "")
    ]
}

struct APIAddress: Sendable {
    let base: URL
    let endpoint: URL
    let origin: String

    init(baseURL: String, protocolKind: APIProtocol) throws {
        let text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw APIConfigurationError.invalidAddress
        }
        guard scheme == "https" || (scheme == "http" && Self.isLoopback(host)) else {
            throw APIConfigurationError.insecureAddress
        }
        components.scheme = scheme
        components.host = host
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty { components.path = "/" + components.path }
        guard !components.path.hasSuffix("/chat/completions"), !components.path.hasSuffix("/messages"),
              !components.path.hasSuffix("/responses") else {
            throw APIConfigurationError.fullEndpoint
        }
        guard let base = components.url else { throw APIConfigurationError.invalidAddress }
        self.base = base
        self.endpoint = base.appendingPathComponent(protocolKind.endpointPath)
        self.origin = "\(scheme)://\(host):\(components.port ?? (scheme == "https" ? 443 : 80))"
    }

    static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" { return true }
        let numbers = host.split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count == 4 && numbers[0] == "127" && numbers.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && (Int(part).map { (0...255).contains($0) } ?? false)
        }
    }
}

enum APIConfigurationError: LocalizedError {
    case invalidAddress, insecureAddress, fullEndpoint, missingName, missingModel, missingKey, keychain(OSStatus), persistence

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "请输入有效接口根地址；不要包含用户名、密码、查询参数或片段。"
        case .insecureAddress: "云端接口必须使用 HTTPS；HTTP 仅允许 localhost、127.x.x.x 或 ::1。"
        case .fullEndpoint: "请移除末尾的 /chat/completions、/messages 或 /responses，填写接口根地址。"
        case .missingName: "请填写配置名称。"
        case .missingModel: "请填写 Model ID。"
        case .missingKey: "请为当前服务填写 API Key。"
        case .keychain(let status): "Keychain 操作失败（\(status)）；密钥未写入普通配置。"
        case .persistence: "无法保存 Tess 配置，请检查应用数据目录。"
        }
    }
}

@MainActor @Observable
final class APIConfigurationStore {
    private(set) var configurations: [APIConfiguration] = []
    private(set) var currentID: UUID?
    private(set) var lastError: String?
    @ObservationIgnored private let localStore: LocalStore
    @ObservationIgnored private let credentialService: String
    @ObservationIgnored private let credentialRemover: ((UUID) throws -> Void)?

    var current: APIConfiguration? { configurations.first { $0.id == currentID } }
    var hasRecoveryFiles: Bool { localStore.hasRecoveryFiles }
    var hasUnreadableFiles: Bool { !localStore.unreadableNames.isEmpty }
    var hasSaveFailure: Bool { !localStore.failedWrites.isEmpty }

    init(storageDirectory: URL? = nil, credentialService: String = "com.caine.Tess.text-api",
         credentialRemover: ((UUID) throws -> Void)? = nil) {
        let directory = storageDirectory ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Tess", isDirectory: true)
        localStore = LocalStore(directory: directory)
        self.credentialService = credentialService
        self.credentialRemover = credentialRemover
        switch localStore.read(SavedState.self, name: "api-configurations.json") {
        case .value(let state):
            configurations = state.configurations
            currentID = configurations.contains { $0.id == state.currentID } ? state.currentID : nil
        case .missing: break
        case .unreadable:
            lastError = "Tess 文字配置无法读取，原文件尚未改动。重新保存前会先保留恢复副本。"
        }
    }

    @discardableResult
    func save(_ value: APIConfiguration, apiKey: String? = nil) -> Bool {
        var value = value
        var createdCredential: UUID?
        do {
            value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            value.modelID = value.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            value.workspaceID = value.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.name.isEmpty else { throw APIConfigurationError.missingName }
            guard !value.modelID.isEmpty else { throw APIConfigurationError.missingModel }
            let address = try APIAddress(baseURL: value.baseURL, protocolKind: value.protocolKind)
            value.baseURL = address.base.absoluteString
            let old = configurations.first { $0.id == value.id }
            value.credentialID = old?.credentialOrigin == address.origin ? old?.credentialID : nil
            value.credentialOrigin = value.credentialID == nil ? nil : address.origin
            if let apiKey {
                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                value.credentialID = nil
                value.credentialOrigin = nil
                if !key.isEmpty {
                    guard !key.contains("\n"), !key.contains("\r") else { throw APIConfigurationError.missingKey }
                    let id = UUID()
                    try writeKey(key, id: id)
                    createdCredential = id
                    value.credentialID = id
                    value.credentialOrigin = address.origin
                }
            }
            if old?.processingIdentity != value.processingIdentity {
                value.testStatus = old == nil ? .untested : .changed
                value.testedAt = nil
                value.testedModel = nil
                value.testMessage = nil
            } else if let old {
                value.testStatus = old.testStatus
                value.testedAt = old.testedAt
                value.testedModel = old.testedModel
                value.testMessage = old.testMessage
            }
            var next = configurations
            if let index = next.firstIndex(where: { $0.id == value.id }) { next[index] = value }
            else { next.append(value) }
            try persist(next, currentID: currentID)
            configurations = next
            if let oldID = old?.credentialID, oldID != value.credentialID { try removeKey(id: oldID) }
            lastError = nil
            return true
        } catch {
            if let id = createdCredential, !configurations.contains(where: { $0.credentialID == id }) { try? removeKey(id: id) }
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard let old = configurations.first(where: { $0.id == id }) else { return true }
        let next = configurations.filter { $0.id != id }
        let nextID = currentID == id ? nil : currentID
        var recovery: URL?
        do {
            // Keep a recoverable credential reference across the file/Keychain boundary.
            if old.credentialID != nil {
                recovery = try localStore.recoveryCopy(SavedState(configurations: configurations, currentID: currentID), name: "api-configurations.json")
            }
            try persist(next, currentID: nextID)
        } catch {
            lastError = recovery == nil ? error.localizedDescription
                : "配置删除未完成，密钥未删除。原配置引用已保留在恢复文件中。"
            return false
        }
        do {
            if let credentialID = old.credentialID { try removeKey(id: credentialID) }
        } catch {
            let credentialError = error
            do { try persist(configurations, currentID: currentID) }
            catch {
                lastError = "密钥未删除，配置恢复也未能保存。配置引用已保留在恢复文件中，请先查看恢复文件。"
                return false
            }
            if let recovery { try? localStore.discardRecoveryCopy(recovery) }
            lastError = credentialError.localizedDescription
            return false
        }
        configurations = next
        currentID = nextID
        if let recovery { try? localStore.discardRecoveryCopy(recovery) }
        lastError = nil
        return true
    }

    @discardableResult
    func setCurrent(_ id: UUID?) -> Bool {
        guard id == nil || configurations.contains(where: { $0.id == id }) else { return false }
        do {
            try persist(configurations, currentID: id)
            currentID = id
            lastError = nil
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    @discardableResult
    func retryLocalSave() -> Bool {
        do {
            try persist(configurations, currentID: currentID)
            lastError = nil
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    @discardableResult
    func markTested(_ snapshot: APIConfiguration, result: TextResult) -> Bool {
        guard !result.isCancelled, let index = configurations.firstIndex(where: { $0.id == snapshot.id }),
              configurations[index].processingIdentity == snapshot.processingIdentity else { return false }
        guard result.error != nil || result.modelID != nil else {
            lastError = "尚未取得文字服务响应；请使用非空样例和整理模式进行实际测试。"
            return false
        }
        var next = configurations
        next[index].testStatus = result.error == nil ? .passed : .failed
        next[index].testedAt = Date()
        next[index].testedModel = result.modelID ?? snapshot.modelID
        next[index].testMessage = result.error?.message ?? (result.warnings.isEmpty ? "连接及正文格式通过；请检查样例表达质量。" : "连接通过；样例存在保真风险，请对照原文。")
        do {
            try persist(next, currentID: currentID)
            configurations = next
            lastError = nil
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    func apiKey(for configuration: APIConfiguration) throws -> String? {
        guard let id = configuration.credentialID else { return nil }
        let address = try APIAddress(baseURL: configuration.baseURL, protocolKind: configuration.protocolKind)
        guard address.origin == configuration.credentialOrigin else { return nil }
        var query = keyQuery(id: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw APIConfigurationError.keychain(status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    private struct SavedState: Codable {
        var configurations: [APIConfiguration]
        var currentID: UUID?
    }

    private func persist(_ configurations: [APIConfiguration], currentID: UUID?) throws {
        do {
            try localStore.write(SavedState(configurations: configurations, currentID: currentID), name: "api-configurations.json")
        } catch { throw APIConfigurationError.persistence }
    }

    private func keyQuery(id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: credentialService,
         kSecAttrAccount as String: id.uuidString, kSecAttrSynchronizable as String: false]
    }

    private func writeKey(_ key: String, id: UUID) throws {
        var query = keyQuery(id: id)
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIConfigurationError.keychain(status) }
    }

    private func removeKey(id: UUID) throws {
        if let credentialRemover { try credentialRemover(id); return }
        let status = SecItemDelete(keyQuery(id: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIConfigurationError.keychain(status) }
    }
}
