#if TESS_INTERNAL_CHECKS
import SwiftUI

/// Synthetic states never construct AppModel, open the microphone, or persist results.
struct HUDPreviewCard: View {
  var isEnglish = false
  var autoplay = false
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @State private var quiet = false
  @State private var visible = false
  @State private var snapshot = HUDSnapshot(phase: .preparing, title: "准备录音")
  @State private var demo: Task<Void, Never>?
  @State private var showsExample = false

  private var reduceMotion: Bool { systemReduceMotion || quiet }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(tr("输入浮层预览", "Input overlay preview")).font(.system(size: 18, weight: .semibold))
        Text(tr("隔离演示 · 使用测试信号，不会录音、调用服务或修改结果。",
                "Isolated demo · Test signals only. No recording, services, or saved results."))
          .font(.system(size: 12)).foregroundStyle(SettingsTheme.secondary)
      }

      ZStack(alignment: .top) {
        RoundedRectangle(cornerRadius: 16).fill(SettingsTheme.sidebar)
        VStack(spacing: 0) {
          HStack {
            Image(systemName: "apple.logo")
            TessWordmark(size: 13)
            Spacer()
            TessStateIcon(menuBar: true, size: 18, motion: TessIconMotion(phase: snapshot.phase),
                          isActive: visible, previewReduceMotion: reduceMotion)
              .frame(width: 22, height: 22)
            Text(tr("原生动效样板", "Native motion sample"))
          }
          .font(.system(size: 10, weight: .medium)).foregroundStyle(SettingsTheme.secondary)
          .padding(.horizontal, 15).frame(height: 25)
          .background(SettingsTheme.foreground.opacity(0.04))
          Spacer()
        }.clipShape(RoundedRectangle(cornerRadius: 16))

        HUDView(snapshot: snapshot,
                onStop: complete,
                onCancel: cancel,
                onRetry: play,
                onResult: { showsExample = true },
                previewReduceMotion: reduceMotion, isVisible: visible)
          .opacity(visible ? 1 : 0)
          .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: visible)
          .padding(.top, 40)
          .allowsHitTesting(visible)
          .accessibilityHidden(!visible)
        if !visible {
          Text(tr("点击“播放全流程”查看", "Press Play full flow to begin"))
            .font(.system(size: 12)).foregroundStyle(SettingsTheme.secondary)
            .padding(.top, 133)
        }
      }.frame(height: 400)

      HStack(spacing: 8) {
        Button(tr("播放全流程", "Play full flow"), action: play)
        Button(tr("失败与重试", "Failure & retry"), action: fail)
        Button(tr("取消", "Cancel"), action: cancel)
        Button(tr("快速再次唤起", "Quick reentry"), action: play)
      }.buttonStyle(SettingsButtonStyle())
      Toggle(tr("预览减少动态效果", "Preview Reduce Motion"), isOn: $quiet)
        .toggleStyle(.checkbox).font(.system(size: 12))
        .disabled(systemReduceMotion)
      Text(showsExample
           ? tr("示例结果：明天下午三点讨论方案。此文本仅属于预览。", "Example result: Discuss the plan tomorrow at 3 pm. Preview only.")
           : tr("绿色音柱表示最近的音量；处理阶段显示实际步骤，不表示百分比。", "The green bars show recent amplitude. Processing steps are not a percentage."))
        .font(.system(size: 11)).foregroundStyle(SettingsTheme.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(22)
    .background(SettingsTheme.background, in: RoundedRectangle(cornerRadius: 18))
    .preferredColorScheme(.light).foregroundStyle(SettingsTheme.foreground)
    .onAppear { if autoplay { play() } }
    .onDisappear { demo?.cancel(); demo = nil; visible = false }
  }

  private func play() {
    demo?.cancel()
    showsExample = false
    snapshot = state(.preparing, "正在准备录音", "Preparing to record", "录音开始前会显示准备状态", "Preparing is separate from recording")
    visible = true
    demo = Task { @MainActor in
      guard await pause(0.6) else { return }
      snapshot = state(.recording, "正在聆听", "Listening", "说完后点击停止", "Press Stop when you finish")
      // Fixed synthetic amplitude sequence, explicitly labeled by the preview.
      let signal: [Float] = [0.04, 0.08, 0.16, 0.36, 0.64, 0.79, 0.5, 0.26, 0.12, 0.28, 0.58, 0.86, 0.6, 0.32, 0.16, 0.04]
      for tick in 0..<65 {
        guard await pause(0.08) else { return }
        snapshot.elapsed = Double(tick + 1) * 0.08
        let silent = (26..<42).contains(tick)
        snapshot.levels = Array((snapshot.levels + [silent ? 0 : signal[tick % signal.count]]).suffix(32))
        snapshot.isSilent = silent
        if tick == 10 { snapshot.transcript = tr("明天下午", "Tomorrow afternoon") }
        if tick == 20 { snapshot.transcript = tr("明天下午三点", "Tomorrow at three") }
        if tick == 42 { snapshot.transcript = tr("明天下午三点讨论方案。", "Discuss the plan tomorrow at 3 pm.") }
      }
      await finishFlow()
    }
  }

  private func complete() {
    demo?.cancel()
    demo = Task { @MainActor in await finishFlow() }
  }

  @MainActor private func finishFlow() async {
    snapshot = state(.transcribing, "正在识别语音", "Transcribing speech", "在本机处理录下的声音", "Processing audio on this Mac")
    guard await pause(1.1) else { return }
    snapshot = state(.processing, "正在整理文字", "Editing text", "通过你配置的文字服务", "Using your configured text service")
    guard await pause(1.2) else { return }
    snapshot = state(.delivering, "正在输出", "Delivering text", "核对会话开始时的输入位置", "Checking the original input target")
    guard await pause(0.8) else { return }
    snapshot = state(.copied, "已复制文字", "Text copied", "回到输入框后按 ⌘V 粘贴", "Return to the text field and press ⌘V")
    guard await pause(2.5) else { return }
    visible = false
  }

  private func fail() {
    demo?.cancel()
    visible = true
    snapshot = state(.failed, "暂时未能完成识别", "Couldn’t finish transcription", "录下的声音仍可重试", "The recording is available to retry")
    snapshot.canRetry = true
  }

  private func cancel() {
    demo?.cancel()
    visible = true
    snapshot = state(.cancelled, "已取消", "Cancelled", "本次内容不会输出", "Nothing from this session will be delivered")
    demo = Task { @MainActor in
      guard await pause(0.9) else { return }
      visible = false
    }
  }

  private func state(_ phase: HUDPhase, _ zh: String, _ en: String, _ detail: String, _ detailEn: String) -> HUDSnapshot {
    HUDSnapshot(phase: phase, title: tr(zh, en), subtitle: tr(detail, detailEn), mode: tr("轻整理 · 测试信号", "Light edit · Test signal"), isEnglish: isEnglish,
                transcript: [.transcribing, .processing, .delivering].contains(phase)
                  ? tr("明天下午三点讨论方案。", "Discuss the plan tomorrow at 3 pm.") : "")
  }

  private func pause(_ seconds: Double) async -> Bool {
    do { try await Task.sleep(for: .seconds(seconds)); return !Task.isCancelled }
    catch { return false }
  }

  private func tr(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
}

#endif
