import Foundation

@main struct SpeechCorrectionCheck {
    static let vocabulary = SpeechVocabulary(enabled: true, words: [
        SpeechWord(spelling: "PRD", meaning: "产品需求文档", aliases: ["PLD", "P R D"]),
        SpeechWord(spelling: "token", meaning: "模型文本计量单位", aliases: ["偷看了"]),
        SpeechWord(spelling: "SwiftUI", meaning: "Apple 界面框架", aliases: ["Swift UI"])
    ])
    static func validate(_ original: String, corrected: String? = nil, edits: [TermEdit] = [], suggestions: [TermEdit] = [],
                         mode: TextMode = .raw, output: String? = nil, prompt: TextPrompt? = nil) throws -> ContextCorrection.Response {
        let response = ContextCorrection.Response(corrected: corrected ?? original, edits: edits, suggestions: suggestions,
                                                  output: output ?? corrected ?? original)
        return try ContextCorrection.validate(String(decoding: JSONEncoder().encode(response), as: UTF8.self), original: original,
                                              vocabulary: vocabulary, mode: mode, prompt: prompt)
    }
    static func rejects(_ action: () throws -> Void) {
        do { try action(); preconditionFailure("Unsafe correction accepted") } catch {}
    }
    static func main() async throws {
        let term = TermEdit(source: "PLD", replacement: "PRD", occurrence: 0, basis: .vocabulary, evidence: "需求")
        let token = TermEdit(source: "偷看了", replacement: "token", occurrence: 0, basis: .vocabulary, evidence: "模型")
        _ = try validate("给移动端写一份 PLD，包含用户场景和需求", corrected: "给移动端写一份 PRD，包含用户场景和需求", edits: [term])
        _ = try validate("这次模型调用的偷看了消耗是多少", corrected: "这次模型调用的token消耗是多少", edits: [token])
        for text in ["这颗 PLD 需要重新编程", "把 PLD 发给我", "不是 PRD，是 PLD", "他说“PLD”，指产品需求", "产品需求中听成 PLD 而不是 PRD"] {
            _ = try validate(text)
            rejects { _ = try validate(text, corrected: text.replacingOccurrences(of: "PLD", with: "PRD"), edits: [term]) }
        }
        rejects { _ = try validate("他偷看了我的笔记", corrected: "他 token 我的笔记", edits: [token]) }
        let chinese = TermEdit(source: "云输入", replacement: "语音输入", occurrence: 0, basis: .suggestion, evidence: "录音浮窗")
        let chineseOriginal = "每次云输入时，录音浮窗显示的文字太少"
        let candidate = try validate(chineseOriginal, suggestions: [chinese])
        precondition(candidate.output == chineseOriginal)
        rejects { _ = try validate(chineseOriginal, suggestions: [chinese], output: "每次语音输入时，录音浮窗显示的文字太少") }
        var unsupported = chinese; unsupported.basis = .vocabulary
        rejects { _ = try validate(chineseOriginal, corrected: "每次语音输入时，录音浮窗显示的文字太少", edits: [unsupported]) }
        for text in ["你看，又听成云输入了，而不是语音输入", "我们讨论的是云输入方案，不是语音输入"] { _ = try validate(text) }
        let explicit = TermEdit(source: "不是PRD，是PLD", replacement: "PLD", occurrence: 0, basis: .spokenCorrection, evidence: "不是PRD，是PLD")
        _ = try validate(explicit.source, corrected: "PLD", edits: [explicit])
        rejects { _ = try validate("他说“不是PRD，是PLD”", corrected: "他说“PLD”", edits: [explicit]) }
        rejects { _ = try validate("她说不是PRD，是PLD", corrected: "她说PLD", edits: [explicit]) }
        let path = "这份 PLD 产品需求文件在 /tmp/PLD.json，周四交，预算 3000 元，不要改"
        _ = try validate(path, corrected: "这份 PRD 产品需求文件在 /tmp/PLD.json，周四交，预算 3000 元，不要改", edits: [term])
        var inPath = term; inPath.occurrence = 1
        rejects { _ = try validate(path, corrected: path.replacingOccurrences(of: "PLD", with: "PRD"), edits: [term, inPath]) }
        for mutated in [path.replacingOccurrences(of: "3000", with: "5000"), path.replacingOccurrences(of: "不要", with: "要"),
                        path.replacingOccurrences(of: "周四", with: "周三"), path.replacingOccurrences(of: "/tmp/", with: "/var/")] {
            rejects { _ = try validate(path, corrected: mutated) }
        }
        rejects { _ = try validate("产品需求 XPLD", corrected: "产品需求 XPRD", edits: [term]) }
        rejects { _ = try validate("产品需求 PLD", corrected: "产品需求 PRD", edits: [term, term]) }
        var missing = term; missing.occurrence = 99
        rejects { _ = try validate("产品需求 PLD", edits: [missing]) }
        rejects { _ = try ContextCorrection.validate("not JSON", original: "原文", vocabulary: vocabulary, mode: .raw, prompt: nil) }
        let translation = TextPrompt.defaults.first { $0.id == "english" }!
        _ = try validate("产品需求 PLD", corrected: "产品需求 PRD", edits: [term], mode: .custom1,
                         output: "The product requirements document, PRD.", prompt: translation)
        rejects { _ = try validate(chineseOriginal, suggestions: [chinese], mode: .custom1,
                                   output: "每次语音输入时，录音浮窗显示的文字太少", prompt: TextPrompt.defaults.first { $0.id == "cleanup" }) }
        precondition(vocabulary.asrContext?.contains("PRD") == true && vocabulary.asrContext?.contains("PLD") == false)
        var disabled = vocabulary; disabled.enabled = false
        precondition(disabled.asrContext == nil && disabled.activeWords.isEmpty)
        var bounded = vocabulary
        bounded.words = (0..<80).map { SpeechWord(spelling: "Word\($0)", meaning: String(repeating: "背景", count: 70)) }
        precondition(bounded.activeWords.count == 50 && bounded.asrContext!.count <= 2_000)
        let material = try ContextCorrection.material("产品需求 PLD", vocabulary: vocabulary)
        precondition(material.contains("PRD") && !material.contains("token") && !material.contains("SwiftUI"))
        let copy = try JSONDecoder().decode(SpeechVocabulary.self, from: JSONEncoder().encode(vocabulary))
        precondition(copy == vocabulary)
        for protocolKind in APIProtocol.allCases {
            var configuration = APIConfiguration()
            configuration.protocolKind = protocolKind; configuration.baseURL = "https://example.com/v1"
            let address = try APIAddress(baseURL: configuration.baseURL, protocolKind: protocolKind)
            let request = try TextService().makeRequest("产品需求 PLD", mode: .raw, configuration: configuration,
                                                       address: address, key: "isolated", correction: vocabulary)
            precondition(request.timeoutInterval == 8)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            precondition(messages.last?["content"] == material)
            let system = protocolKind == .anthropic ? body["system"] as! String : messages[0]["content"]!
            precondition(system.contains("suggestions") && system.contains("不是 PRD，是 PLD"))
        }
        let noService = await TextService().process("保留原文", mode: .raw, configuration: nil, correction: vocabulary)
        precondition(noService.output == "保留原文" && noService.error?.category == .configuration)
        if let endpoint = ProcessInfo.processInfo.environment["TESS_TEST_TEXT_URL"] {
            var configuration = APIPreset.all.first { $0.id == "ollama" }!.configuration()
            configuration.baseURL = endpoint; configuration.modelID = "correct"
            let service = TextService()
            let success = await service.process("产品需求 PLD", mode: .raw, configuration: configuration, correction: vocabulary)
            precondition(success.output == "产品需求 PRD" && success.correction?.edits.count == 1 && success.error == nil)
            configuration.modelID = "invalid"
            let invalid = await service.process("产品需求 PLD", mode: .raw, configuration: configuration, correction: vocabulary)
            precondition(invalid.output == "产品需求 PLD" && invalid.error != nil && invalid.correction == nil)
            configuration.modelID = "slow"
            let slowConfiguration = configuration
            let cancellation = Task { await service.process("产品需求 PLD", mode: .raw, configuration: slowConfiguration, correction: vocabulary) }
            try await Task.sleep(for: .milliseconds(100)); cancellation.cancel()
            let cancelled = await cancellation.value
            precondition(cancelled.isCancelled && cancelled.output == "产品需求 PLD")
            let timeout = await service.process("产品需求 PLD", mode: .raw, configuration: configuration, correction: vocabulary)
            precondition(timeout.error?.category == .timeout && timeout.output == "产品需求 PLD" && timeout.elapsed < 9.5)
        }
        print("Speech correction checks passed: context bounds, opt-in data, PRD/token ambiguity, Chinese suggestions, explicit correction, quotes, facts/paths, malformed/overlapping edits, template separation, original fallback and local HTTP cancellation/8-second timeout.")
    }
}
