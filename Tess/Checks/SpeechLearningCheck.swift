import Foundation

@MainActor enum SpeechLearningCheck {
    static func run(root: URL) async throws {
        func changes(_ a: String, _ b: String) -> [String] { SpeechDiff.differences(from: a, to: b).map { $0.mistaken + "→" + $0.spelling } }
        precondition(changes("请写一份 PLD 给我。", "请写一份 PRD 给我。") == ["PLD→PRD"])
        precondition(changes("这次云输入很方便。", "这次语音输入很方便。") == ["云输入→语音输入"])
        precondition(changes("请写一份 PLD，然后核对偷看了消耗。", "请写一份 PRD，然后核对token消耗。").count == 2)
        precondition(changes("👨‍👩‍👧‍👦 请把 cafo 发给我🇨🇳。", "👨‍👩‍👧‍👦 请把 cafe\u{301} 发给我🇨🇳。") == ["cafo→cafe\u{301}"])
        let longStart = ProcessInfo.processInfo.systemUptime
        precondition(changes(String(repeating: "甲", count: 8_000), String(repeating: "乙", count: 8_000)).isEmpty)
        precondition(ProcessInfo.processInfo.systemUptime - longStart < 2, "Large rewrites must have bounded work")
        for pair in [("PLD 和 PLD 都要看", "PRD 和 PLD 都要看"), ("请看一下。", "请看一下！"),
                     ("请发给 我", "请发给我"), ("周五交稿", "周六交稿"), ("预算100元", "预算1000元"),
                     ("我需要修改", "我不需要修改"), ("读取 /tmp/foo 文件", "读取 /tmp/bar 文件"),
                     ("用 userName 取值", "用 userID 取值"), ("打开 https://a.com", "打开 https://b.com"),
                     ("给我看看最初的方案细节。", "全部改成另外一个完全不同的想法。"), ("先看看甲再看看乙", "先看看乙再看看甲")] {
            precondition(changes(pair.0, pair.1).isEmpty, "Unsafe/ambiguous edit: \(pair)")
        }
        let prefix = "👨‍👩‍👧‍👦 e\u{301} 前缀：", suffix = "；其余内容"
        let selection = NSRange(location: prefix.utf16.count, length: 2)
        let inserted = "请写一份 PLD 给我。"
        let before = prefix + "旧字" + suffix
        let after = prefix + inserted + suffix
        let anchor = SpeechInsertionAnchor.verify(before: before, selection: selection, inserted: inserted, after: after)!
        precondition(anchor.extract(from: prefix + "请写一份 PRD 给我。" + suffix) == "请写一份 PRD 给我。")
        precondition(anchor.extract(from: "改了前缀" + after) == nil)
        precondition(anchor.extract(from: "") == nil)
        precondition(anchor.extract(from: prefix + String(repeating: "字", count: 8_001) + suffix) == nil)
        precondition(SpeechInsertionAnchor.verify(before: before, selection: selection, inserted: inserted, after: before) == nil)
        precondition(SpeechInsertionAnchor.verify(before: inserted, selection: NSRange(location: 0, length: 0), inserted: inserted, after: inserted + inserted) == nil)
        precondition(SpeechInsertionAnchor.verify(before: "😀", selection: NSRange(location: 1, length: 0), inserted: "词", after: "词😀") == nil)

        var edits: [String] = []
        let fixture = SpeechInputObservation.Fixture(field: after)
        let observer = SpeechInputObservation { edits.append($0) }
        observer.prepareForCheck(before: before, selection: selection, inserted: inserted, fixture: fixture)
        await observer.verifyAndStart()
        precondition(observer.isObservingForCheck)
        fixture.field = prefix + "请写一份 PRD 给我。" + suffix
        observer.notifyForCheck(); observer.notifyForCheck()
        try await Task.sleep(for: .milliseconds(1_100))
        precondition(edits == ["请写一份 PRD 给我。"], "Notifications must debounce")
        fixture.field = after
        observer.notifyForCheck()
        try await Task.sleep(for: .milliseconds(1_100))
        precondition(edits.last == inserted, "Undo must be reported so candidates can disappear")
        fixture.field = ""
        observer.notifyForCheck()
        precondition(!observer.isObservingForCheck && edits.count == 2)
        for stopReason in ["unsupported", "focus", "timeout", "late", "noPaste", "outside", "tooLarge", "readbackTimeout"] {
            let io = SpeechInputObservation.Fixture(field: stopReason == "noPaste" ? before : after)
            io.notificationsSupported = stopReason != "unsupported"
            let probe = SpeechInputObservation { _ in preconditionFailure("Stopped observer emitted an edit: \(stopReason)") }
            probe.prepareForCheck(before: before, selection: selection, inserted: inserted, fixture: io)
            if stopReason == "readbackTimeout" { io.time = 1.1 }
            await probe.verifyAndStart()
            if stopReason == "focus" { io.identityValid = false; probe.tickForCheck() }
            if stopReason == "timeout" { io.time = 120; probe.tickForCheck() }
            if stopReason == "outside" { io.field = after + "新内容"; probe.notifyForCheck() }
            if stopReason == "tooLarge" { io.field = String(repeating: "字", count: 8_001); probe.notifyForCheck() }
            if stopReason == "late" { probe.stop(); probe.notifyForCheck() }
            precondition(!probe.isObservingForCheck, stopReason)
        }

        let directory = root.appendingPathComponent("learning", isDirectory: true)
        setenv("TESS_DATA_DIRECTORY", directory.path, 1)
        let app = AppModel()
        defer { app.shutdown() }
        app.preferences.completedOnboarding = true
        precondition(app.preferences.speechLearningEnabled != true)
        app.setSpeechLearning(true)
        let baseline = SpeechBaseline(sessionID: UUID(), original: inserted, delivered: inserted, mode: "raw", textProcessed: false,
            applicationID: "test.editor", applicationName: "Editor", model: "qwenSmall", promptSnapshotID: UUID(), promptVersion: 1)
        func resetResult(_ baseline: SpeechBaseline? = nil, origin: String = "voice") {
            app.draft = nil
            app.recent = SavedResult(original: inserted, output: inserted, mode: .raw, origin: origin, speechBaseline: baseline)
        }
        resetResult(baseline)
        let id = app.result!.id
        precondition(!app.submitSpeechEdit("错误配对", resultID: UUID(), revision: 0))
        precondition(app.submitSpeechEdit("请写一份 PRD 给我。", resultID: id, revision: 0))
        try await Task.sleep(for: .milliseconds(1_100))
        let stale = app.learningReview!
        precondition(app.speechMemories.isEmpty, "Unconfirmed edits are not hints")
        app.editOutput(inserted)
        precondition(app.learningReview == nil)
        precondition(!app.rememberSpeechDifference(stale.differences[0], review: stale))
        app.editOutput("请写一份 PRD 给我。")
        try await Task.sleep(for: .milliseconds(1_100))
        let review = app.learningReview!
        precondition(app.rememberSpeechDifference(review.differences[0], review: review))
        precondition(app.speechMemories.count == 1)
        precondition(!app.rememberSpeechDifference(review.differences[0], review: review), "Duplicate click must not count")
        let saved = app.speechMemories[0]
        let local = LocalStore(directory: directory)
        if case .value(let records) = local.read([SpeechMemory].self, name: SpeechLearning.fileName) { precondition(records == [saved]) }
        else { preconditionFailure("Memory was not persisted") }
        let fileMode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(SpeechLearning.fileName).path)[.posixPermissions] as! NSNumber
        precondition(fileMode.intValue == 0o600)
        func snapshot(enabled: Bool = true, appID: String? = "test.editor", vocabulary: SpeechVocabulary = SpeechVocabulary(), supports: Bool = true) -> SpeechPromptSnapshot {
            .make(vocabulary: vocabulary, learningEnabled: enabled, memories: app.speechMemories, applicationID: appID, supportsHints: supports)
        }
        precondition(snapshot().context == "PRD", "Manual vocabulary may be disabled")
        precondition(snapshot(enabled: false).context == nil && snapshot(appID: "other").context == nil && snapshot(appID: nil).context == nil)
        precondition(snapshot(supports: false).context == nil, "Whisper must not receive hints")
        let frozen = snapshot()
        var disabled = saved; disabled.enabled = false
        precondition(app.updateSpeechMemory(disabled))
        precondition(snapshot().context == nil && frozen.context == "PRD")
        precondition(app.updateSpeechMemory(saved))
        var conflicting = saved
        conflicting = SpeechMemory(mistaken: "PLD", spelling: "PSD", applicationID: "test.editor", applicationName: "Editor",
            allApplications: false, confirmedAt: Date(), source: .resultPage, resultID: UUID())
        precondition(SpeechLearning.conflicts(in: [saved, conflicting]).count == 2)
        let paused = SpeechPromptSnapshot.make(vocabulary: SpeechVocabulary(), learningEnabled: true, memories: [saved, conflicting], applicationID: "test.editor", supportsHints: true)
        precondition(paused.context == nil && paused.omittedCount == 2)
        var vocabulary = SpeechVocabulary(enabled: true)
        vocabulary.words = (0..<50).map { SpeechWord(spelling: "Word\($0)") }
        precondition(snapshot(vocabulary: vocabulary).memoryIDs.isEmpty && snapshot(vocabulary: vocabulary).omittedCount == 1)
        vocabulary.words = [SpeechWord(spelling: "PRD")]
        precondition(snapshot(vocabulary: vocabulary).context == "PRD")
        vocabulary.words = (0..<50).map { SpeechWord(spelling: "Word\($0)", meaning: String(repeating: "释", count: 160)) }
        let limited = snapshot(vocabulary: vocabulary)
        precondition((limited.context?.count ?? 0) <= 2_000 && limited.omittedCount > 0)
        let remote = try ContextCorrection.material(inserted, vocabulary: SpeechVocabulary())
        precondition(!remote.contains("PRD"), "Personal memories must not enter text-service material")
        app.asr.transcripts = [.success(inserted), .success(inserted)]
        app.startRecording()
        for _ in 0..<100 where !app.isRecording { try await Task.sleep(for: .milliseconds(10)) }
        precondition(app.isRecording)
        app.setSpeechLearning(false)
        app.stopRecording()
        for _ in 0..<100 where app.busy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(app.asr.contexts.last! == "PRD", "Current recording must keep its fixed learning snapshot")
        app.startRecording()
        for _ in 0..<100 where !app.isRecording { try await Task.sleep(for: .milliseconds(10)) }
        app.stopRecording()
        for _ in 0..<100 where app.busy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(app.asr.contexts.last! == nil, "Next recording must honor disabled learning")
        app.setSpeechLearning(true)
        app.undoLastSpeechMemory()
        precondition(app.speechMemories.isEmpty && snapshot().context == nil)

        // Unknown application needs an explicit all-app choice; failures must not claim a save.
        let unknown = SpeechBaseline(sessionID: UUID(), original: inserted, delivered: inserted, mode: "raw", textProcessed: false,
            applicationID: nil, applicationName: nil, model: "qwenSmall", promptSnapshotID: UUID(), promptVersion: 1)
        resetResult(unknown)
        app.editOutput("请写一份 PSD 给我。")
        try await Task.sleep(for: .milliseconds(1_100))
        let unknownReview = app.learningReview!
        precondition(!app.rememberSpeechDifference(unknownReview.differences[0], review: unknownReview))
        let learningFile = directory.appendingPathComponent(SpeechLearning.fileName)
        try FileManager.default.removeItem(at: learningFile)
        try FileManager.default.createDirectory(at: learningFile, withIntermediateDirectories: false)
        precondition(!app.rememberSpeechDifference(unknownReview.differences[0], review: unknownReview, allApplications: true))
        precondition(app.speechMemories.isEmpty)
        try FileManager.default.removeItem(at: learningFile)
        precondition(app.rememberSpeechDifference(unknownReview.differences[0], review: unknownReview, allApplications: true))
        precondition(snapshot(appID: "other").context == "PSD")
        app.setSpeechLearning(false)
        precondition(app.learningReview == nil && app.speechMemories.count == 1)
        let reloaded = AppModel()
        precondition(reloaded.preferences.speechLearningEnabled == false && reloaded.speechMemories.count == 1 && reloaded.learningReview == nil)
        reloaded.shutdown()
        _ = try local.recoveryCopy(app.speechMemories, name: SpeechLearning.fileName)
        app.clearSpeechMemories()
        precondition(app.speechMemories.isEmpty)
        let recovered = try FileManager.default.contentsOfDirectory(atPath: local.recoveryDirectory.path)
        precondition(recovered.isEmpty)
        let legacy = SavedResult(original: inserted, output: inserted, mode: .raw, origin: "voice")
        let restoredLegacy = try JSONDecoder().decode(SavedResult.self, from: JSONEncoder().encode(legacy))
        precondition(restoredLegacy.speechBaseline == nil)
        app.setSpeechLearning(true)
        resetResult(baseline)
        app.reprocess()
        for _ in 0..<100 where app.busy { try await Task.sleep(for: .milliseconds(10)) }
        precondition(app.result?.speechBaseline == baseline && app.result?.speechLearningExcluded == true)
        app.editOutput("请写一份 PCD 给我。")
        try await Task.sleep(for: .milliseconds(1_100))
        precondition(app.learningReview == nil, "Reprocessing retains provenance but excludes learning")
        for origin in ["manual", "screenshot", "voice"] {
            resetResult(origin == "voice" ? nil : baseline, origin: origin)
            app.editOutput("请写一份 PCD 给我。")
            try await Task.sleep(for: .milliseconds(1_100))
            precondition(app.learningReview == nil)
        }
        let processed = SpeechBaseline(sessionID: UUID(), original: inserted, delivered: inserted, mode: "raw", textProcessed: true,
            applicationID: "test.editor", applicationName: nil, model: "qwenSmall", promptSnapshotID: UUID(), promptVersion: 1)
        resetResult(processed)
        app.editOutput("请写一份 PCD 给我。")
        try await Task.sleep(for: .milliseconds(1_100))
        precondition(app.learningReview == nil)
        resetResult(baseline)
        app.recent?.createdAt = Date().addingTimeInterval(-86_401)
        app.editOutput("请写一份 PCD 给我。")
        try await Task.sleep(for: .milliseconds(1_100))
        precondition(app.learningReview == nil && !app.canSubmitSpeechEdit)
        app.showResult()
        precondition(app.result == nil)
        try Data("broken learning JSON".utf8).write(to: learningFile)
        let damaged = AppModel()
        precondition(damaged.speechMemories.isEmpty && damaged.storageNotice != nil)
        damaged.clearSpeechMemories()
        let recoveryAfterClear = try FileManager.default.contentsOfDirectory(atPath: local.recoveryDirectory.path)
        precondition(!recoveryAfterClear.contains { $0.hasSuffix("-" + SpeechLearning.fileName) })
        damaged.shutdown()
        let full = (0..<50).map { index in
            SpeechMemory(mistaken: "Wrong\(index)", spelling: "Term\(index)", applicationID: "test.editor", applicationName: nil,
                allApplications: false, confirmedAt: Date(), source: .resultPage, resultID: UUID())
        }
        try local.write(full, name: SpeechLearning.fileName)
        let saturated = AppModel()
        saturated.setSpeechLearning(true)
        saturated.recent = SavedResult(original: inserted, output: inserted, mode: .raw, origin: "voice", speechBaseline: baseline)
        saturated.editOutput("请写一份 PCD 给我。")
        try await Task.sleep(for: .milliseconds(1_100))
        let atLimit = saturated.learningReview!
        precondition(!saturated.rememberSpeechDifference(atLimit.differences[0], review: atLimit) && saturated.speechMemories.count == 50)
        saturated.shutdown()
        print("Speech learning checks passed: local diff, UTF-16 insertion proof, notification/timeout/focus fixtures, source gates, stale confirmation, persistence failures, scopes/conflicts, prompt budgets, independent switches, restart, expiry, undo and clear/recovery.")
    }
}
