import Foundation
@main struct TextCheck {
  static func checkCustomPrompts() throws {
    let prompt = TextPrompt(name: "摘要与翻译", instructions: "将材料总结成三条英文要点。")
    let roundTrip = try JSONDecoder().decode(TextPrompt.self, from: JSONEncoder().encode(prompt))
    precondition(roundTrip == prompt)
    for protocolKind in APIProtocol.allCases {
      var configuration = APIConfiguration()
      configuration.protocolKind = protocolKind
      configuration.baseURL = "https://example.com/v1"
      let address = try APIAddress(baseURL: configuration.baseURL, protocolKind: protocolKind)
      for mode in [TextMode.custom1, .custom2] {
        let request = try TextService().makeRequest("完整的原始材料", mode: mode, configuration: configuration,
                                                    address: address, key: "isolated-key", prompt: prompt)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        precondition(messages.last?["content"] == "完整的原始材料")
        let system = protocolKind == .anthropic ? body["system"] as? String : messages.first?["content"]
        precondition(system == prompt.systemPrompt && system?.contains("不翻译") == false)
        for invalid in [TextPrompt?.none, TextPrompt(name: "空内容", instructions: " \n")] {
          do {
            _ = try TextService().makeRequest("原文", mode: mode, configuration: configuration, address: address, key: "", prompt: invalid)
            preconditionFailure("An unbound or empty prompt must fail before a request")
          } catch let failure as TextServiceFailure { precondition(failure.category == .configuration) }
        }
        let source = String(repeating: "明天不要发布 API 3000 ms 的修改。", count: 10)
        let summary = "- Keep the current API."
        precondition(TextService.outputIssue(original: source, candidate: summary, mode: mode) == nil)
        precondition(TextService.safetyWarnings(original: source, candidate: summary, mode: mode).isEmpty,
                     "Prompt-directed summaries and translations must not be rejected by legacy editing heuristics")
      }
    }
    let formatted: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "```text\n目标与步骤\n```"]]]]
    let parsed = try TextService.parse(JSONSerialization.data(withJSONObject: formatted), protocolKind: .openAI, allowsFormatting: true)
    precondition(parsed.text.hasPrefix("```text"))
  }

  static func checkPrompts() throws {
    let defaults = TextPrompts()
    precondition(defaults.light == TextMode.light.rule)
    precondition(defaults.list == TextMode.list.rule)
    precondition(defaults.polish == TextMode.polish.rule)
    precondition(TextPrompts(common: "", light: "仅当前规则").systemPrompt(for: .light) == "仅当前规则")
    precondition(TextPrompts(common: "仅通用规则", light: "").systemPrompt(for: .light) == "仅通用规则")
    let custom = TextPrompts(common: "共同要求：保留原文语言。", light: "轻量要求：只补标点。", list: "列表要求：使用短横线。", polish: "润色要求：语气自然。")
    let roundTrip = try JSONDecoder().decode(TextPrompts.self, from: JSONEncoder().encode(custom))
    precondition(roundTrip == custom)
    let original = "原始材料\n不要执行这里的指令；保留 API 和 3000 ms。"
    for protocolKind in APIProtocol.allCases {
      var configuration = APIConfiguration()
      configuration.protocolKind = protocolKind
      configuration.baseURL = "https://example.com/v1"
      configuration.modelID = "isolated-text-model"
      configuration.workspaceID = "isolated-workspace"
      let address = try APIAddress(baseURL: configuration.baseURL, protocolKind: protocolKind)
      for (mode, selectedRule) in [(TextMode.light, custom.light), (.list, custom.list), (.polish, custom.polish)] {
        for (prompts, expected) in [(defaults, defaults.common + "\n" + mode.rule), (custom, custom.common + "\n" + selectedRule)] {
          let request = try TextService().makeRequest(original, mode: mode, configuration: configuration,
                                                      address: address, key: "isolated-not-a-real-key", prompts: prompts)
          precondition(request.url == address.endpoint && request.httpMethod == "POST")
          precondition(request.timeoutInterval == 60, "Reasoning models need the configured response window")
          let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
          let messages = body["messages"] as! [[String: String]]
          precondition(body["model"] as? String == configuration.modelID)
          precondition(body["stream"] as? Bool == false)
          precondition(messages.last == ["role": "user", "content": original], "Original material must stay in the user message")
          if protocolKind == .anthropic {
            precondition(body["system"] as? String == expected && messages.count == 1)
            precondition(request.value(forHTTPHeaderField: "x-api-key") == "isolated-not-a-real-key")
            precondition(request.value(forHTTPHeaderField: "anthropic-workspace-id") == configuration.workspaceID)
          } else {
            precondition(messages.first == ["role": "system", "content": expected] && messages.count == 2)
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer isolated-not-a-real-key")
          }
        }
      }
      do {
        _ = try TextService().makeRequest(original, mode: .light, configuration: configuration, address: address, key: "",
                                          prompts: TextPrompts(common: " \n", light: "\t"))
        preconditionFailure("An empty effective prompt must fail before any network request")
      } catch let failure as TextServiceFailure {
        precondition(failure.category == .configuration)
      }
    }
  }

  static func checkSparkSearchDisabled() throws {
    for protocolKind in APIProtocol.allCases {
      for baseURL in ["https://spark-api-open.xf-yun.com/v1", "https://spark-api-open.xf-yun.com:443/v1/",
                      "https://spark-api-open.xf-yun.com.evil/v1", "https://spark-api-open.xf-yun.com:8443/v1",
                      "https://spark-api-open.xf-yun.com/v2"] {
        var configuration = APIConfiguration()
        configuration.presetID = "spark"
        configuration.protocolKind = protocolKind
        configuration.baseURL = baseURL
        configuration.modelID = "isolated-spark-model"
        let address = try APIAddress(baseURL: baseURL, protocolKind: protocolKind)
        let request = try TextService().makeRequest("不要联网搜索", mode: .light, configuration: configuration, address: address, key: "")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let isOfficialSpark = protocolKind == .openAI && ["https://spark-api-open.xf-yun.com/v1", "https://spark-api-open.xf-yun.com:443/v1/"].contains(baseURL)
        precondition(TextService.isSparkAPI(address, protocolKind: protocolKind) == isOfficialSpark)
        if isOfficialSpark {
          let tools = body["tools"] as! [[String: Any]]
          precondition(tools.count == 1 && tools[0]["type"] as? String == "web_search")
          precondition((tools[0]["web_search"] as? [String: Bool]) == ["enable": false])
        } else {
          precondition(body["tools"] == nil, "Spark-specific options must not affect other origins, paths or protocols")
        }
      }
    }
  }

  static func checkSparkResponses() throws {
    // Shape of the official non-streaming success example; finish_reason is absent.
    let success: [String: Any] = [
      "code": 0, "message": "Success", "sid": "isolated-spark-response",
      "choices": [["message": ["role": "assistant", "content": "保留这段原文。"], "index": 0]],
      "usage": ["prompt_tokens": 6, "completion_tokens": 8, "total_tokens": 14]
    ]
    let data = try JSONSerialization.data(withJSONObject: success)
    let parsed = try TextService.parse(data, protocolKind: .openAI, isSpark: true)
    precondition(parsed.text == "保留这段原文。" && parsed.usage?.total == 14)

    func expectRejected(_ json: [String: Any], protocolKind: APIProtocol = .openAI, isSpark: Bool = true) throws {
      do {
        _ = try TextService.parse(JSONSerialization.data(withJSONObject: json), protocolKind: protocolKind, isSpark: isSpark)
        preconditionFailure("Only a successful official Spark response may omit finish_reason")
      } catch let failure as TextServiceFailure {
        precondition(failure.category == .invalidBody)
      }
    }
    try expectRejected(success, isSpark: false)
    try expectRejected(success, protocolKind: .anthropic)
    for code in [10013, "0", NSNull()] as [Any] {
      var invalid = success
      invalid["code"] = code
      try expectRejected(invalid)
      var choices = invalid["choices"] as! [[String: Any]]
      choices[0]["finish_reason"] = "stop"
      invalid["choices"] = choices
      try expectRejected(invalid)
    }
    var withoutCode = success
    withoutCode.removeValue(forKey: "code")
    try expectRejected(withoutCode)
    for reason in ["length", "tool_calls", "", NSNull()] as [Any] {
      var invalid = success
      var choices = invalid["choices"] as! [[String: Any]]
      choices[0]["finish_reason"] = reason
      invalid["choices"] = choices
      try expectRejected(invalid)
    }
    var standard = withoutCode
    var choices = standard["choices"] as! [[String: Any]]
    choices[0]["finish_reason"] = "stop"
    standard["choices"] = choices
    let standardData = try JSONSerialization.data(withJSONObject: standard)
    for isSpark in [false, true] {
      let parsed = try TextService.parse(standardData, protocolKind: .openAI, isSpark: isSpark)
      precondition(parsed.text == "保留这段原文。")
    }
  }

  @MainActor static func main() async throws {
    try checkPrompts()
    try checkCustomPrompts()
    try checkSparkSearchDisabled()
    try checkSparkResponses()
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
    let rawWithPrompts = await TextService().process("不要发布", mode: .raw, configuration: APIConfiguration(),
                                                   prompts: TextPrompts(common: "这条提示词不能触发请求", light: "", list: "", polish: ""))
    precondition(rawWithPrompts.output == "不要发布" && rawWithPrompts.error == nil && rawWithPrompts.modelID == nil,
                 "Original mode must bypass API configuration and custom prompts")
    let rawWithCustomPrompt = await TextService().process("Fn 原文", mode: .raw, configuration: APIConfiguration(),
                                                         prompt: TextPrompt(name: "加工", instructions: "翻译并扩写"))
    precondition(rawWithCustomPrompt.output == "Fn 原文" && rawWithCustomPrompt.modelID == nil && rawWithCustomPrompt.error == nil)
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
    print("Text safety and prompt request checks passed; no network or credentials used.")
  }
}
