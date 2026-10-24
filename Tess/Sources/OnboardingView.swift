import AppKit
import AVFoundation
import SwiftUI

struct OnboardingView: View {
  @Bindable var app: AppModel
  @State private var microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  @State private var accessibilityAllowed = false
  private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private var step: Int { min(4, max(0, app.preferences.onboardingStep ?? 0)) }
  private var model: ASRModel { app.asr.selectedModel }
  private var downloading: Bool {
    switch app.asr.states[model] {
    case .connecting, .fetchingManifest, .downloading, .verifying: true
    default: false
    }
  }
  private var ready: Bool { microphoneAllowed && accessibilityAllowed && app.asr.isReady(model) }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 12) {
        TessAvatar(size: 42)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          TessWordmark(size: 32)
          Text("苔丝").font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsTheme.secondary)
        }
        Spacer()
        Picker("Language", selection: $app.preferences.language) {
          Text("简体中文").tag(InterfaceLanguage.chinese)
          Text("English").tag(InterfaceLanguage.english)
          Text(app.tr("跟随系统", "System")).tag(InterfaceLanguage.system)
        }.labelsHidden().frame(width: 125)
          .onChange(of: app.preferences.language) { _, _ in app.savePreferences() }
      }
      HStack(spacing: 8) {
        ForEach(0..<5) { index in Capsule().fill(index <= step ? SettingsTheme.accent : SettingsTheme.border).frame(height: 3) }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          switch step {
          case 0: welcome
          case 1: permissions
          case 2: speechModel
          case 3: practice
          default: externalInput
          }
          LocalStorageNotice(app: app)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      Spacer(minLength: 0)
      HStack {
        if step > 0 { Button(app.tr("上一步", "Back")) { move(to: step - 1) }.disabled(app.busy) }
        Spacer()
        Text(app.tr("第 \(step + 1) 步，共 5 步", "Step \(step + 1) of 5")).font(.caption).foregroundStyle(SettingsTheme.secondary)
        Spacer()
        if step < 4 {
          Button(app.tr(step == 0 ? "开始设置" : "继续", step == 0 ? "Get started" : "Continue")) { move(to: step + 1) }
            .buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large)
            .disabled(!canContinue || app.busy)
        } else {
          Button(app.tr("已确认输入成功，完成", "Text appeared — finish")) {
            app.preferences.completedOnboarding = true
            app.savePreferences()
            app.hideWindows?()
          }.buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large)
            .disabled(!ready || app.preferences.onboardingPracticePassed != true || app.busy)
        }
      }.buttonStyle(SettingsButtonStyle())
    }
    .padding(32).padding(.top, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SettingsTheme.background).foregroundStyle(SettingsTheme.foreground)
    .tint(SettingsTheme.accent).preferredColorScheme(.light)
    .onAppear { refreshPermissions() }
    .onReceive(refresh) { _ in refreshPermissions() }
  }

  private var canContinue: Bool {
    switch step {
    case 1: microphoneAllowed && accessibilityAllowed
    case 2: app.asr.isReady(model)
    case 3: ready && app.preferences.onboardingPracticePassed == true
    default: true
    }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 22) {
      TessMascot(height: 164).frame(maxWidth: .infinity)
      heading(app.tr("说话，文字就到输入框", "Speak into any text field"),
              app.tr("按住快捷键说话，松开后输入文字。先花几步完成设置，再试说一句。", "Hold your shortcut to speak, then release to insert your words. Set up Tess and try a sentence."))
      Label(app.tr("语音在这台 Mac 上识别", "Speech recognition runs on this Mac"), systemImage: "desktopcomputer")
      Label(app.tr("基础听写无需账号或 API Key", "No account or API key for dictation"), systemImage: "checkmark.shield")
      Text(app.tr("关闭窗口后，可从菜单栏的 Tess 图标继续设置。", "Close this window anytime and resume from the Tess menu bar icon."))
        .font(.callout).foregroundStyle(SettingsTheme.secondary)
    }
  }

  private var permissions: some View {
    VStack(alignment: .leading, spacing: 18) {
      heading(app.tr("允许 Tess 聆听和输入", "Let Tess listen and type"),
              app.tr("权限由 macOS 管理。完成授权后返回这里，状态会自动更新。", "macOS manages these permissions. Return here after allowing access; the status updates automatically."))
      SettingsCard(title: app.tr("麦克风", "MICROPHONE")) {
        permissionRow(allowed: microphoneAllowed, detail: app.tr("仅在你开始录音后采集声音。", "Audio is captured only when you start recording.")) {
          if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio); refreshPermissions() }
          } else { openPermission("Privacy_Microphone") }
        }
      }
      SettingsCard(title: app.tr("辅助功能", "ACCESSIBILITY")) {
        permissionRow(allowed: accessibilityAllowed, detail: app.tr("用于快捷键和把文字输入到你选中的输入框。", "Used for shortcuts and inserting text into your selected field.")) {
          app.delivery.requestAccessibilityPermission()
          openPermission("Privacy_Accessibility")
        }
      }
      Text(app.tr("选区截图会在首次使用时单独请求屏幕权限。", "Screen permission is requested when you first take a screenshot."))
        .font(.callout).foregroundStyle(SettingsTheme.secondary)
    }
  }

  private var speechModel: some View {
    VStack(alignment: .leading, spacing: 18) {
      heading(app.tr("准备本地语音识别", "Prepare local dictation"),
              app.asr.usesBundledModel(model)
              ? app.tr("基础语音模型已随应用提供，可以直接离线使用。其他模型可稍后在设置中选择。", "The basic speech model is included. Dictate offline right away; more models are available in Settings.")
              : app.tr("首次下载后即可离线听写。其他模型可稍后在设置中选择。", "Download once to dictate offline. More models are available in Settings."))
      SettingsCard(title: model.title) {
        VStack(alignment: .leading, spacing: 14) {
          let progress = app.asr.downloadProgress[model]
          let total = progress?.total ?? model.estimatedBytes
          if !app.asr.usesBundledModel(model) {
            Text(app.tr("下载约 \(bytes(total)) · 需要 \(bytes(ASRModel.requiredFreeBytes(for: total))) 可用空间", "About \(bytes(total)) to download · \(bytes(ASRModel.requiredFreeBytes(for: total))) free space needed"))
          }
          if app.asr.isReady(model) {
            Label(app.tr("模型已校验，可以继续", "Model verified. Ready to continue"), systemImage: "checkmark.circle.fill").foregroundStyle(SettingsTheme.accent)
          } else if downloading {
            ProgressView(value: progress?.fraction)
            Text(app.asr.states[model]?.label ?? "")
            if let progress { Text("\(bytes(progress.received)) / \(bytes(total))").monospacedDigit() }
            Button(app.tr("取消下载", "Cancel download")) { app.asr.cancelDownload(model) }.buttonStyle(SettingsButtonStyle())
          } else {
            if let error = app.asr.lastError { Text(error).foregroundStyle(SettingsTheme.warning).textSelection(.enabled) }
            Button(app.tr("下载语音模型", "Download speech model")) {
              app.savePreferences()
              Task { await app.asr.download(model) }
            }.buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large)
          }
          Text(app.asr.usesBundledModel(model)
               ? app.tr("Qwen3-ASR · Apache 2.0 · 音频仅在本机处理", "Qwen3-ASR · Apache 2.0 · Audio stays on this Mac")
               : app.tr("来源：Hugging Face。下载失败可重试，完整文件会保留。", "Source: Hugging Face. Retry keeps completed files."))
            .font(.caption).foregroundStyle(SettingsTheme.secondary)
        }.padding(.vertical, 12)
      }
    }
  }

  private var practice: some View {
    VStack(alignment: .leading, spacing: 18) {
      heading(app.tr("试说一句", "Try a sentence"),
              app.tr("例如：今天下午三点，提醒我检查 SwiftUI 的设置页面。练习内容只显示在这里。", "For example: Remind me to review the SwiftUI settings at three this afternoon. Practice text stays here."))
      Text(app.tr("快捷键：", "Shortcut: ") + (app.preferences.bindings[.record]?.label ?? app.tr("未绑定", "Unbound")))
        .font(.title3.weight(.medium))
      HStack {
        Button(app.tr("调整快捷键或麦克风", "Adjust shortcut or microphone")) { app.showSettings(.general) }.disabled(app.busy)
        Button(app.tr("Fn 系统设置", "Fn system settings")) {
          NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        }
      }.buttonStyle(SettingsButtonStyle())
      Text(app.tr("若 Fn 同时弹出表情或系统听写，在键盘设置中将其动作改为“不执行操作”，或选择其他快捷键。", "If Fn opens emoji or system dictation, set its action to Do Nothing in Keyboard settings, or choose another shortcut."))
        .font(.caption).foregroundStyle(SettingsTheme.secondary)
      if !ready {
        Button(app.tr("权限或模型未就绪，返回检查", "Permissions or model need attention")) { move(to: 1) }.buttonStyle(SettingsButtonStyle())
      }
      if app.isRecording {
        ProgressView(value: Double(app.recorder.levelHistory.last ?? 0)).tint(SettingsTheme.accent)
      }
      Text(app.isPracticing && !app.liveTranscript.isEmpty ? app.liveTranscript : app.practiceTranscript.isEmpty
           ? app.tr("识别到的文字会出现在这里", "Your transcript will appear here") : app.practiceTranscript)
        .font(.system(size: 18)).textSelection(.enabled)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading).padding(16)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 12))
      if !app.status.isEmpty { Text(app.status).font(.callout).foregroundStyle(SettingsTheme.secondary) }
      HStack {
        if app.isRecording {
          Button(app.tr("结束试说", "Finish recording")) { app.stopRecording() }.buttonStyle(.borderedProminent).foregroundStyle(.white)
        } else {
          Button(app.tr("开始试说", "Start practice")) { app.startRecording(mode: .raw) }
            .buttonStyle(.borderedProminent).foregroundStyle(.white).disabled(app.busy || !ready)
        }
        if app.busy { Button(app.tr("取消", "Cancel")) { app.cancel() }.buttonStyle(SettingsButtonStyle()) }
        if app.preferences.onboardingPracticePassed == true {
          Label(app.tr("已完成语音识别", "Speech recognition completed"), systemImage: "checkmark.circle.fill").foregroundStyle(SettingsTheme.accent)
        }
      }
    }
  }

  private var externalInput: some View {
    VStack(alignment: .leading, spacing: 20) {
      heading(app.tr("把文字写到其他应用", "Try another app"),
              app.tr("最后确认一次实际输入，之后就可以从菜单栏随时使用 Tess。", "Confirm that text arrives in another app, then use Tess from the menu bar anytime."))
      Text(app.tr("1. 打开文本编辑或常用应用，点击一个空白输入框。\n\n2. 按住录音快捷键说一句话，松开结束；Fn 也可轻点开始、再点结束。\n\n3. 确认文字进入原输入框，再回到这里完成设置。", "1. Open TextEdit or your usual app and click an empty text field.\n\n2. Hold your recording shortcut, speak and release. Fn also supports tap to start, tap again to stop.\n\n3. Confirm the text appeared, then return here to finish setup."))
        .font(.system(size: 16)).lineSpacing(5)
      Button(app.tr("打开文本编辑", "Open TextEdit")) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
          NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
      }.buttonStyle(SettingsButtonStyle())
      Text(app.tr("如果提示“已复制”，说明没有确认到输入位置。请检查辅助功能权限并重新定位输入框后再试。Tess 不会自动发送消息。", "If Tess says Copied, it could not confirm an input destination. Check Accessibility permission and refocus your field before retrying. Tess never sends messages automatically."))
        .font(.callout).foregroundStyle(SettingsTheme.secondary)
      Button(app.tr("检查权限与快捷键", "Check permissions and shortcuts")) { app.showSettings(.general) }.buttonStyle(SettingsButtonStyle())
      if !ready { Button(app.tr("返回授权步骤", "Return to permissions")) { move(to: 1) }.buttonStyle(SettingsButtonStyle()) }
    }
  }

  private func heading(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.system(size: 28, weight: .semibold))
      Text(detail).font(.system(size: 15)).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func permissionRow(allowed: Bool, detail: String, action: @escaping () -> Void) -> some View {
    HStack {
      Text(detail).fixedSize(horizontal: false, vertical: true)
      Spacer()
      if allowed { Label(app.tr("已允许", "Allowed"), systemImage: "checkmark.circle.fill").foregroundStyle(SettingsTheme.accent) }
      else { Button(app.tr("允许访问", "Allow access"), action: action).buttonStyle(SettingsButtonStyle()) }
    }.padding(.vertical, 16)
  }
  private func move(to value: Int) { app.preferences.onboardingStep = value; app.savePreferences() }
  private func refreshPermissions() {
    microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    let allowed = app.delivery.hasAccessibilityPermission
    if allowed != accessibilityAllowed { accessibilityAllowed = allowed; app.hotkeys.refreshFn() }
  }
  private func openPermission(_ anchor: String) {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
  }
  private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}
