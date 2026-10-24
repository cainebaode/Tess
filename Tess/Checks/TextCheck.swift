import Foundation
@main struct TextCheck {
  @MainActor static func main() async throws {
    let endpoint = try APIAddress(baseURL: "https://example.com/v1/", protocolKind: .openAI)
    precondition(endpoint.endpoint.absoluteString == "https://example.com/v1/chat/completions")
    for url in ["http://example.com/v1", "http://127.0.0.1.evil/v1", "https://key@example.com/v1", "https://example.com/v1?key=abc", "https://example.com/v1/chat/completions"] {
      precondition((try? APIAddress(baseURL: url, protocolKind: .openAI)) == nil)
    }
    precondition((try? APIAddress(baseURL: "http://[::1]:11434/v1", protocolKind: .openAI)) != nil)
    precondition(!TextService.safetyWarnings(original: "把 timeout 设成 3000 ms，别改 retry_count", candidate: "把 timeout 设成 5000 ms，改 retry_count", mode: .light).isEmpty)
    precondition(TextService.safetyWarnings(original: "明天下午三点，哦不，四点开会，只请产品和开发参加", candidate: "明天下午四点开会，只请产品和开发参加。", mode: .light).isEmpty)
    precondition(TextService.safetyWarnings(original: "I checked the API", candidate: "I checked the API.", mode: .light).isEmpty)
    for path in ["/Users/test/code", "~/code", ".env", "../code", "C:\\code"] {
      precondition(!TextService.safetyWarnings(original: "保留 \(path)", candidate: "保留 code", mode: .light).isEmpty)
    }
    precondition(TextService.outputIssue(original: "先查看页面", candidate: "好的，这是整理后的内容：先查看页面。") != nil)
    precondition(TextService.outputIssue(original: "抱歉，今天无法参加", candidate: "抱歉，今天无法参加。") == nil)
    precondition(TextService.outputIssue(original: String(repeating: "保留已说明的工作内容", count: 12), candidate: "整理工作内容。") != nil)
    let raw = await TextService().process("不要发布", mode: .raw, configuration: nil)
    precondition(raw.output == "不要发布" && raw.error == nil)
    let scratch = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/verification/checks/config-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let store = APIConfigurationStore(storageDirectory: scratch)
    var configuration = APIPreset.all.first { $0.id == "ollama" }!.configuration()
    configuration.modelID = "synthetic-check-only"
    precondition(store.save(configuration))
    let saved = store.configurations[0]
    precondition(!store.markTested(saved, result: raw))
    var valid = raw
    valid.modelID = configuration.modelID
    precondition(store.markTested(saved, result: valid))
    configuration.modelID = "changed-model"
    precondition(store.save(configuration))
    precondition(store.configurations[0].testStatus == .changed)
    let oversized = await TextService().process(String(repeating: "中", count: 8001), mode: .light, configuration: nil)
    precondition(oversized.output.count == 8001 && oversized.error?.category == .configuration)
    print("Text safety checks passed; no network or credentials used.")
  }
}
