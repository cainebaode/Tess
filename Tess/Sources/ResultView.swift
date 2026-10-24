import SwiftUI

struct ResultView: View {
  @Bindable var app: AppModel
  @State private var showOriginal = false
  var body: some View {
    if !app.preferences.completedOnboarding {
      OnboardingView(app: app)
    } else {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        TessAvatar(size: 48)
        VStack(alignment: .leading, spacing: 4) {
          TessWordmark(size: 32)
          Text(app.tr("苔丝 · 说出来，写清楚", "Speak freely. Write clearly.")).font(.caption).foregroundStyle(SettingsTheme.secondary)
        }
        Spacer()
        Button { app.openSettings?() } label: { Image(systemName: "gearshape") }
          .buttonStyle(SettingsButtonStyle())
          .help(app.tr("设置", "Settings")).accessibilityLabel(app.tr("设置", "Settings"))
      }
      LocalStorageNotice(app: app)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if app.showingManualInput { manualInput }
          else if app.result == nil {
            emptyResult
          }
          else { result }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      if !app.showingManualInput, app.result != nil { resultActions }
      if !app.status.isEmpty {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: app.busy ? "clock" : "info.circle")
          Text(app.status).textSelection(.enabled).lineLimit(3)
        }.font(.caption).foregroundStyle(SettingsTheme.secondary)
      }
      if app.canRetryTranscription {
        Button(app.tr("重试识别（录音仅在内存保留 10 分钟）", "Retry transcription (audio kept in memory for 10 minutes)")) { app.retryTranscription() }
          .buttonStyle(SettingsButtonStyle())
      }
      HStack {
        Button(app.tr("语音输入", "Dictate")) { app.startRecording() }
          .disabled(app.busy)
        Button(app.tr("选区截图", "Screenshot")) { app.takeScreenshot() }.disabled(app.busy)
        Button(app.tr("粘贴文字", "Paste text")) { app.newText() }.disabled(app.busy)
        Spacer()
        if app.busy { Button(app.tr("取消", "Cancel")) { app.cancel() } }
        else if app.result != nil { Button(app.tr("清除", "Clear")) { app.clearTemporaryContent() } }
      }.buttonStyle(SettingsButtonStyle())
    }
    .padding(28).padding(.top, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SettingsTheme.background)
    .foregroundStyle(SettingsTheme.foreground)
    .preferredColorScheme(.light)
    .tint(SettingsTheme.accent)
    .onChange(of: app.result?.id) { _, _ in showOriginal = false }
    }
  }

  private var emptyResult: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(app.tr("准备好下一次输入", "Ready for your next thought"))
        .font(.system(size: 25, weight: .semibold))
      Text(app.tr("完成的文字会保留在这里，随时查看原文、修改或重新复制。暂存内容最多保留 24 小时。", "Your next result will appear here, with the original text available to review, edit or copy again. Temporary content is kept for up to 24 hours."))
        .foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
      SettingsCard(title: app.tr("开始输入", "START INPUT")) {
        if !app.asr.isReady(app.asr.selectedModel) {
          SettingsRow(title: app.tr("语音模型尚未就绪", "A speech model is needed"), description: app.tr("先下载一个本地模型；截图和粘贴文字仍可使用。", "Download a local model. Screenshots and pasted text remain available.")) {
            Button(app.tr("下载模型", "Get a model")) { app.showSettings(.speech) }.buttonStyle(SettingsButtonStyle())
          }
        } else {
          SettingsRow(title: app.tr("把光标放入目标输入框", "Place the cursor in your destination"),
                      description: app.preferences.bindings[.record]?.isFn == true && !app.hotkeys.fnEnabled
                      ? app.tr("Fn 尚未启用，可在快捷键设置中启用。", "Fn is not enabled yet. Set it up in Shortcuts.")
                      : app.preferences.bindings[.record]?.label ?? app.tr("从菜单栏开始录音", "Start dictation from the menu bar")) {
            Button(app.tr("查看快捷键", "View shortcuts")) { app.showSettings(.general) }.buttonStyle(SettingsButtonStyle())
          }
        }
      }
    }.padding(.vertical, 14)
  }

  private var manualInput: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(app.tr("粘贴需要整理的文字", "Paste text to edit")).font(.title2.weight(.semibold))
        Spacer()
        Button(app.tr("返回结果", "Back to result")) { app.closeManualInput() }.buttonStyle(SettingsButtonStyle()).disabled(app.busy)
      }
      Text(app.tr("在下方主动粘贴（⌘V）。Tess 不会在后台读取剪贴板。", "Paste here with ⌘V. Tess does not read your clipboard in the background."))
        .font(.caption).foregroundStyle(SettingsTheme.secondary)
      TextEditor(text: Binding(get: { app.manualText }, set: { app.editManualText($0) })).font(.system(size: 15)).scrollContentBackground(.hidden)
        .padding(12).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .frame(height: 250).disabled(app.busy)
        .accessibilityLabel(app.tr("待整理文字", "Text to edit"))
      HStack {
        modePicker
        Text("\(app.manualText.count) / 8,000").font(.caption).foregroundStyle(SettingsTheme.secondary)
        Spacer()
        Button(app.tr("预览结果", "Preview result")) { app.processManual() }
          .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.regular)
          .disabled(app.manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.busy)
      }
      textServiceHint
    }
  }

  private var result: some View {
    VStack(alignment: .leading, spacing: 14) {
      if app.result?.imageName != nil {
        screenshotCard
        if app.result?.original.isEmpty == true {
          Button(app.tr("添加语音说明", "Add voice note")) { app.startRecording(attachingToScreenshot: true) }.buttonStyle(SettingsButtonStyle()).disabled(app.busy)
        }
      }
      HStack {
        Picker(app.tr("显示内容", "Displayed text"), selection: $showOriginal) {
          Text(app.tr("结果", "Result")).tag(false)
          Text(app.tr("原文", "Original")).tag(true)
        }.labelsHidden().pickerStyle(.segmented).frame(width: 190)
        Spacer()
        modePicker
        Button(app.tr("重新处理", "Reprocess")) { showOriginal = false; app.reprocess() }
          .buttonStyle(SettingsButtonStyle()).disabled(app.busy || app.result?.original.isEmpty == true)
      }
      if showOriginal {
        ScrollView { Text(app.result?.original ?? "").frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(14) }
          .frame(height: app.result?.imageName == nil ? 220 : 160).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 14))
      } else {
        TextEditor(text: Binding(get: { app.result?.output ?? "" }, set: { app.editOutput($0) }))
          .font(.system(size: 15)).scrollContentBackground(.hidden)
          .padding(12).frame(height: app.result?.imageName == nil ? 220 : 160).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 14))
          .disabled(app.busy)
          .accessibilityLabel(app.tr("结果文字，可编辑", "Result text, editable"))
      }
      if let message = app.result?.message, !message.isEmpty {
        Text(message).font(.caption).foregroundStyle(SettingsTheme.warning).textSelection(.enabled)
      }
      if let candidate = app.result?.candidate {
        DisclosureGroup(app.tr("检查未通过的候选结果（未自动使用）", "Candidate held for review")) {
          ScrollView { Text(candidate).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 120)
        }.font(.caption)
      }
      textServiceHint
    }
  }

  @ViewBuilder private var screenshotCard: some View {
    if let url = app.imageURL, let image = NSImage(contentsOf: url) {
        HStack(spacing: 16) {
          Image(nsImage: image).resizable().scaledToFit().frame(width: 170, height: 115)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(app.tr("选区截图预览", "Selection screenshot preview"))
          VStack(alignment: .leading, spacing: 9) {
            Text(app.tr("选区截图", "Selection screenshot")).font(.headline)
            Text(app.tr("图片仅在本机暂存。先粘贴图片，再复制文字。", "Stored locally. Paste the image before copying the text."))
              .font(.caption).foregroundStyle(SettingsTheme.secondary)
            HStack {
              Button(app.tr("复制图片", "Copy image")) { app.status = app.capture.copyImage(url) ? app.tr("已复制图片，请在目标应用粘贴并确认。", "Image copied. Paste and confirm in the destination app.") : app.tr("图片复制失败", "Image copy failed") }
              Button(app.tr("保存 PNG", "Save PNG")) {
                if let saved = app.capture.saveImage(url) {
                  app.status = saved ? app.tr("图片已保存", "Image saved") : (app.capture.lastError ?? app.tr("保存失败", "Save failed"))
                }
              }
              Menu { Button(app.tr("重新截图", "Retake")) { app.takeScreenshot() }; Button(app.tr("移除图片", "Remove")) { app.removeImage() } } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel(app.tr("截图操作", "Screenshot actions"))
            }.buttonStyle(SettingsButtonStyle()).disabled(app.busy)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16))
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Label(app.tr("截图暂时无法读取", "Screenshot unavailable"), systemImage: "photo.badge.exclamationmark")
          .font(.headline)
        Text(app.tr("文字仍可查看和复制。请重新截图，或移除这张图片。", "Your text is still available to review and copy. Retake the screenshot or remove the image."))
          .font(.caption).foregroundStyle(SettingsTheme.secondary)
        HStack {
          Button(app.tr("重新截图", "Retake")) { app.takeScreenshot() }
          Button(app.tr("移除图片", "Remove image")) { app.removeImage() }
        }.buttonStyle(SettingsButtonStyle()).disabled(app.busy)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private var resultActions: some View {
    HStack {
        Button(app.tr("使用原文", "Use original")) { showOriginal = false; app.useOriginal() }
          .disabled((app.busy && !app.isTextProcessing) || app.result?.original.isEmpty == true)
        Spacer()
        Button(app.tr("复制文字", "Copy text")) { app.copyResult() }
          .disabled(app.busy || app.result?.output.isEmpty == true)
          .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.regular)
        Button(app.tr("选择输入位置…", "Choose destination…")) { app.insertManually() }
          .disabled(app.busy || app.result?.output.isEmpty == true)
    }.buttonStyle(SettingsButtonStyle())
  }

  @ViewBuilder private var textServiceHint: some View {
    if app.configurations.current?.testStatus != .passed {
      Button(app.tr("需要整理文字？配置并测试文字服务", "Want text cleanup? Configure and test a text service")) { app.showSettings(.text) }
        .buttonStyle(.plain).font(.caption).foregroundStyle(SettingsTheme.accent)
    }
  }

  private var modePicker: some View {
    Picker(app.tr("模式", "Mode"), selection: $app.preferences.textMode) {
      ForEach(TextMode.allCases) { mode in
        Text(app.modeTitle(mode)).tag(mode)
          .disabled(mode != .raw && app.configurations.current?.testStatus != .passed)
      }
    }.labelsHidden().frame(width: 140)
      .onChange(of: app.preferences.textMode) { _, _ in app.savePreferences() }
  }
}

struct LocalStorageNotice: View {
  var app: AppModel

  var body: some View {
    if let notice = app.storageNotice {
      VStack(alignment: .leading, spacing: 10) {
        Label(notice, systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(SettingsTheme.warning)
          .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        HStack {
          Button(app.tr("重试保存", "Retry save")) { app.retryLocalSave() }
          if app.storageRecoveryAvailable {
            Button(app.tr("查看恢复文件", "Show recovery files")) { app.revealStorageRecovery() }
          }
        }.buttonStyle(SettingsButtonStyle())
      }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(SettingsTheme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
  }
}
