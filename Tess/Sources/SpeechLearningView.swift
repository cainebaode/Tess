import SwiftUI

struct SpeechLearningSettings: View {
    var app: AppModel
    @State private var confirmClear = false

    var body: some View {
        SettingsCard(title: app.tr("从纠正中学习", "LEARN FROM CORRECTIONS")) {
            Toggle(app.tr("从我的纠正中学习", "Learn from my corrections"), isOn: Binding(
                get: { app.preferences.speechLearningEnabled == true }, set: { app.setSpeechLearning($0) }
            )).toggleStyle(.switch).padding(.vertical, 12)
            Text(app.tr("纯听写改字后，在最近结果确认“这是听错了吗”。确认的词只在本机保存，下次 Qwen 识别时参考；不会训练模型或保存日常录音。关闭后停止采集和使用记忆，已有记录保留。",
                        "After editing plain dictation, confirm recognition mistakes in the recent result. Confirmed words stay on this Mac and guide the next Qwen recognition. No model training or daily audio storage. Turning this off stops collection and hints while keeping saved memories."))
                .font(.caption).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if app.asr.selectedModel == .whisper {
                Text(app.tr("此模型暂不使用个人学习提示。", "This model does not use personal learning hints yet."))
                    .font(.caption).foregroundStyle(SettingsTheme.warning)
            }
            if app.speechPromptOmittedCount > 0 {
                Text(app.tr("上次录音有 \(app.speechPromptOmittedCount) 项因上限或冲突未包含在提示中；记录仍保留。",
                            "The last recording omitted \(app.speechPromptOmittedCount) hints due to limits or conflicts. Records are still saved."))
                    .font(.caption).foregroundStyle(SettingsTheme.warning)
            }
            DisclosureGroup(app.tr("已学习内容", "Learned words") + " · \(app.speechMemories.count) / 50") {
                if app.speechMemories.isEmpty {
                    Text(app.tr("尚未确认任何纠正。", "No corrections confirmed yet.")).font(.caption).padding(.vertical, 8)
                }
                ForEach(app.speechMemories) { memory in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("\(memory.mistaken) → \(memory.spelling)", isOn: Binding(
                                get: { memory.enabled }, set: { enabled in
                                    var next = memory; next.enabled = enabled; _ = app.updateSpeechMemory(next)
                                }
                            )).toggleStyle(.switch)
                            Button(app.tr("删除", "Delete")) { app.deleteSpeechMemory(memory.id) }.buttonStyle(SettingsButtonStyle())
                        }
                        Picker(app.tr("适用范围", "Scope"), selection: Binding(
                            get: { memory.allApplications }, set: { all in
                                var next = memory; next.allApplications = all; _ = app.updateSpeechMemory(next)
                            }
                        )) {
                            if let id = memory.applicationID { Text(memory.applicationName ?? id).tag(false) }
                            Text(app.tr("所有应用", "All applications")).tag(true)
                        }.frame(maxWidth: 300)
                        if app.speechMemoryConflicts.contains(memory.id) {
                            Text(app.tr("同一误写存在不同纠正，已暂停提示。请停用其中一项或调整范围。",
                                        "Conflicting corrections are paused. Disable one or adjust the scope."))
                                .font(.caption).foregroundStyle(SettingsTheme.warning)
                        }
                    }.padding(.vertical, 10)
                }
            }.padding(.vertical, 12)
            HStack {
                if app.lastRememberedMemoryID != nil {
                    Button(app.tr("撤销最近一次记住", "Undo last memory")) { app.undoLastSpeechMemory() }
                }
                Spacer()
                Button(app.tr("清空已学习内容…", "Clear learned words…")) { confirmClear = true }
            }.buttonStyle(SettingsButtonStyle()).padding(.bottom, 10)
        }
        .confirmationDialog(app.tr("清空所有已学习内容及待确认纠正？", "Clear all learned words and pending corrections?"), isPresented: $confirmClear) {
            Button(app.tr("清空", "Clear"), role: .destructive) { app.clearSpeechMemories() }
            Button(app.tr("取消", "Cancel"), role: .cancel) {}
        }
    }
}

struct SpeechLearningResult: View {
    var app: AppModel
    @State private var submission: SavedSpeechSubmission?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if app.speechPromptOmittedCount > 0 {
                Text(app.tr("本次录音有 \(app.speechPromptOmittedCount) 项提示因上限或冲突未使用；可在语音识别设置中查看。",
                            "This recording omitted \(app.speechPromptOmittedCount) hints due to limits or conflicts. Review Speech settings."))
                    .font(.caption).foregroundStyle(SettingsTheme.warning)
            }
            if app.canSubmitSpeechEdit, let current = app.result, let baseline = current.speechBaseline {
                Button(app.tr("提交改好的文字…", "Submit corrected text…")) {
                    app.beginSpeechSubmission()
                    submission = SavedSpeechSubmission(id: current.id, revision: current.editRevision ?? 0,
                        date: current.createdAt, baseline: baseline.delivered)
                }.buttonStyle(SettingsButtonStyle())
                Text(app.tr("微信、仅复制或无法读取的输入框：复制改好的整段后，在这里主动粘贴并对照本次结果。",
                            "For WeChat, copied results or unreadable fields: copy your corrected passage and paste it here to compare with this result."))
                    .font(.caption).foregroundStyle(SettingsTheme.secondary)
            }
            if let review = app.learningReview {
                VStack(alignment: .leading, spacing: 10) {
                    Text(app.tr("这是听错了吗？", "Was this a recognition mistake?")).font(.headline)
                    DisclosureGroup(app.tr("查看本次完整对照", "Review the full comparison")) {
                        Text(review.baseline.delivered).textSelection(.enabled).foregroundStyle(SettingsTheme.secondary)
                        Divider()
                        Text(review.edited).textSelection(.enabled)
                    }.font(.caption)
                    Text(app.tr("只记住听错的用词；润色、改变主意或模型生成的修改请忽略。",
                                "Remember only misheard words. Ignore rephrasing, changed intentions or model-generated edits."))
                        .font(.caption).foregroundStyle(SettingsTheme.secondary)
                    ForEach(review.differences) { difference in
                        HStack {
                            Text("\(difference.mistaken) → \(difference.spelling)").textSelection(.enabled)
                            Spacer()
                            Button(review.baseline.applicationID == nil ? app.tr("记住到所有应用", "Remember for all apps") : app.tr("记住", "Remember")) {
                                _ = app.rememberSpeechDifference(difference, review: review, allApplications: review.baseline.applicationID == nil)
                            }
                            Button(app.tr("忽略", "Ignore")) { app.ignoreSpeechDifference(difference) }
                        }.buttonStyle(SettingsButtonStyle()).disabled(app.busy)
                    }
                    Text(review.baseline.applicationID == nil
                         ? app.tr("无法确定原应用；选择“记住到所有应用”才会启用。", "The original app is unknown. Remembering explicitly enables this for all apps.")
                         : app.tr("仅用于：", "Only for: ") + (review.baseline.applicationName ?? review.baseline.applicationID ?? ""))
                        .font(.caption).foregroundStyle(SettingsTheme.secondary)
                }.padding(14).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 14))
            }
            if !app.learningNotice.isEmpty { Text(app.learningNotice).font(.caption).foregroundStyle(SettingsTheme.secondary) }
            if app.lastRememberedMemoryID != nil {
                Button(app.tr("撤销最近一次记住", "Undo last memory")) { app.undoLastSpeechMemory() }.buttonStyle(SettingsButtonStyle())
            }
        }.sheet(item: $submission) { value in SpeechSubmissionView(app: app, submission: value) }
    }
}

private struct SavedSpeechSubmission: Identifiable {
    let id: UUID
    let revision: Int
    let date: Date
    let baseline: String
}

private struct SpeechSubmissionView: View {
    var app: AppModel
    let submission: SavedSpeechSubmission
    @State private var text = ""
    @State private var error = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.tr("提交这次听写的完整改稿", "Submit the corrected passage")).font(.title2.weight(.semibold))
            Text(submission.date, format: .dateTime.month().day().hour().minute()).font(.caption)
            ScrollView { Text(submission.baseline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 100).padding(12).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 12))
            Text(app.tr("确认上方是对应的听写，再在下方粘贴改好的整段。不会读取其他剪贴板内容。",
                        "Check that the dictation above matches, then paste the entire corrected passage below."))
                .font(.caption).foregroundStyle(SettingsTheme.secondary)
            TextEditor(text: $text).font(.system(size: 15)).frame(height: 180).scrollContentBackground(.hidden)
                .padding(12).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 12))
            if error { Text(app.tr("结果已变化或不可学习，请返回后重新选择。", "The result changed or is ineligible. Return and select it again.")).foregroundStyle(SettingsTheme.warning) }
            HStack {
                Button(app.tr("取消", "Cancel")) { dismiss() }
                Text("\(text.count) / 8,000").font(.caption)
                Spacer()
                Button(app.tr("确认对应，开始对照", "Confirm and compare")) {
                    if app.submitSpeechEdit(text, resultID: submission.id, revision: submission.revision) { dismiss() }
                    else { error = true }
                }.buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 8_000 || app.busy)
            }.buttonStyle(SettingsButtonStyle())
        }.padding(24).frame(width: 560).background(SettingsWindowBackdrop()).foregroundStyle(SettingsTheme.foreground)
    }
}
