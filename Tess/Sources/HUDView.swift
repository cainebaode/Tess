import SwiftUI

enum HUDPhase: Equatable, Sendable {
  case preparing, recording, transcribing, processing, delivering
  case copied, completed, failed, cancelled, selectingTarget

  var isBusy: Bool {
    switch self {
    case .preparing, .recording, .transcribing, .processing, .delivering, .selectingTarget: true
    default: false
    }
  }
}

struct HUDSnapshot: Equatable, Sendable {
  var phase: HUDPhase
  var title: String
  var subtitle: String = ""
  var mode: String = ""
  var elapsed: TimeInterval = 0
  var levels: [Float] = []
  var isSilent = false
  var canRetry = false
  var isEnglish = false
  var includesEditing = true
  var canShowResult = true
  var confirmTitle: String? = nil
  var retryTitle: String? = nil
  var settingsTitle: String? = nil
  var transcript = ""
  var sessionID: UUID? = nil
  var hasHeardSpeech = false
  var canUseOriginal = false
}

/// One presentation for live sessions and the explicitly isolated native preview.
/// Top-anchored transitions and the quiet Reduce Motion treatment follow Talkify
/// a880149 (MIT); the Tess layout and amplitude history below are implemented here.
struct HUDView: View {
  let snapshot: HUDSnapshot
  var onStop: () -> Void = {}
  var onCancel: () -> Void = {}
  var onRetry: () -> Void = {}
  var onResult: () -> Void = {}
  var onConfirm: () -> Void = {}
  var onSettings: () -> Void = {}
  var onUseOriginal: () -> Void = {}
  var previewReduceMotion = false
  var isVisible = true
  var cardWidth: CGFloat = 400
  var transcriptHeight: CGFloat = 144
  @State private var followsLatest = true
  @State private var userScrolling = false

  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  private var reduceMotion: Bool { systemReduceMotion || previewReduceMotion }

  private var tint: Color {
    switch snapshot.phase {
    case .failed: .orange
    case .cancelled: SettingsTheme.hudForeground.opacity(0.55)
    case .completed, .copied: SettingsTheme.leaf
    default: SettingsTheme.leaf
    }
  }

  private var symbol: String {
    switch snapshot.phase {
    case .preparing: "mic.badge.plus"
    case .recording: snapshot.isSilent ? "mic" : "mic.fill"
    case .transcribing: "waveform"
    case .processing: "text.alignleft"
    case .delivering: "arrow.up.right"
    case .copied: "doc.on.clipboard"
    case .completed: "checkmark"
    case .failed: "exclamationmark"
    case .cancelled: "xmark"
    case .selectingTarget: "cursorarrow.click"
    }
  }

  private var hasStage: Bool {
    [.preparing, .transcribing, .processing, .delivering].contains(snapshot.phase)
  }
  private var showsTranscript: Bool {
    [.preparing, .recording, .transcribing, .processing, .delivering].contains(snapshot.phase) || !snapshot.transcript.isEmpty
  }
  private var transcriptLabel: String {
    switch snapshot.phase {
    case .recording, .preparing: tr("实时转录 · 未定稿", "Live transcript · Draft")
    case .transcribing: tr("转录草稿 · 正在定稿", "Draft · Finalizing")
    case .processing: tr("转录原文 · 整理中", "Transcript · Editing")
    case .failed: tr("转录草稿 · 未完成", "Draft · Incomplete")
    default: tr("最终文字", "Final text")
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 11) {
        TessStateIcon(size: 34, motion: TessIconMotion(phase: snapshot.phase),
                      isActive: isVisible, previewReduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 4) {
          Text(snapshot.title)
            .font(.system(size: 13, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
          if !snapshot.subtitle.isEmpty {
            Text(snapshot.subtitle)
              .font(.system(size: 11))
              .foregroundStyle(SettingsTheme.hudForeground.opacity(0.68))
              .fixedSize(horizontal: false, vertical: true)
              .lineLimit(3)
              .help(snapshot.subtitle)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 27, height: 27)
          .background(tint.opacity(0.13), in: Circle())
          .accessibilityHidden(true)
      }
      .frame(height: 64)

      if snapshot.phase == .recording {
        amplitudeHistory
          .frame(height: 40)
      } else if hasStage {
        processingStage
          .frame(height: 40)
      } else if showsTranscript {
        Color.clear.frame(height: 40)
      }

      if showsTranscript {
        VStack(alignment: .leading, spacing: 5) {
          ScrollViewReader { reader in
            HStack {
              Text(transcriptLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SettingsTheme.hudForeground.opacity(0.6))
              Spacer(minLength: 4)
              Button(tr("回到最新", "Latest")) {
                followsLatest = true
                reader.scrollTo("transcript-end", anchor: .bottom)
              }
              .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
              .opacity(followsLatest ? 0 : 1).disabled(followsLatest)
              .accessibilityHidden(followsLatest)
            }.frame(height: 18)
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.transcript.isEmpty
                     ? (snapshot.hasHeardSpeech ? tr("正在生成转录…", "Generating transcript…")
                        : tr("说话后，文字会显示在这里。", "Your speech will appear here.")) : snapshot.transcript)
                  .font(.system(size: 15)).lineSpacing(5)
                  .foregroundStyle(SettingsTheme.hudForeground.opacity(snapshot.transcript.isEmpty ? 0.5 : 0.95))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: 8).id("transcript-end")
              }
            }
            .frame(height: transcriptHeight)
            .onScrollPhaseChange { _, phase in
              userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: HUDScrollMetrics.self) { geometry in
              HUDScrollMetrics(offset: geometry.contentOffset.y,
                               bottom: geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
            } action: { old, new in
              if userScrolling, abs(new.offset - old.offset) > 0.5 { followsLatest = new.isAtBottom }
            }
            .onChange(of: snapshot.transcript) { _, _ in
              guard followsLatest else { return }
              Task { @MainActor in
                await Task.yield()
                if followsLatest { reader.scrollTo("transcript-end", anchor: .bottom) }
              }
            }
            .onChange(of: snapshot.sessionID) { old, new in
              if new != nil, new != old { followsLatest = true; reader.scrollTo("transcript-end", anchor: .bottom) }
            }
          }
        }
        .padding(10)
        .background(SettingsTheme.hudForeground.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
      }

      HStack(spacing: 8) {
        if snapshot.phase == .recording {
          Text(String(format: "%d:%02d", Int(snapshot.elapsed) / 60, Int(snapshot.elapsed) % 60))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(SettingsTheme.hudForeground.opacity(0.75))
            .accessibilityLabel(tr("录音时长", "Recording duration"))
        } else if !snapshot.mode.isEmpty {
          Text(snapshot.mode)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(SettingsTheme.hudForeground.opacity(0.58))
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        actions
      }
      .controlSize(.small)
      .frame(height: 30)
    }
    .padding(16)
    .frame(width: cardWidth, alignment: .topLeading)
    .background {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(SettingsTheme.hudBackground)
        .overlay(alignment: .top) {
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom))
        }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(SettingsTheme.hudForeground.opacity(contrast == .increased ? 0.45 : 0.1), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.3), radius: 15, y: 7)
    .preferredColorScheme(.dark)
    .foregroundStyle(SettingsTheme.hudForeground)
    .accessibilityElement(children: .contain)
  }

  /// These are 32 recent RMS amplitudes, not PCM samples or a frequency spectrum.
  private var amplitudeHistory: some View {
    let recent = Array(snapshot.levels.suffix(32))
    let values = Array(repeating: Float.zero, count: max(0, 32 - recent.count)) + recent
    return VStack(spacing: 8) {
      if reduceMotion {
        GeometryReader { geometry in
          Capsule().fill(SettingsTheme.hudForeground.opacity(0.08))
            .overlay(alignment: .leading) {
              Capsule().fill(tint)
                .frame(width: max(3, geometry.size.width * CGFloat(values.last ?? 0)))
            }
        }.frame(height: 4).padding(.vertical, 5)
      } else {
        HStack(alignment: .center, spacing: 4) {
          ForEach(values.indices, id: \.self) { index in
            Capsule()
              .fill(LinearGradient(colors: [SettingsTheme.hudForeground, tint],
                                   startPoint: .top, endPoint: .bottom))
              .opacity(0.3 + Double(index) / 31 * 0.7)
              .frame(width: 5, height: max(3, CGFloat(min(1, max(0, values[index]))) * 18))
          }
        }
        .frame(maxWidth: .infinity).frame(height: 18)
        .animation(.linear(duration: 0.08), value: values)
        .shadow(color: tint.opacity(Double(values.last ?? 0) * 0.32), radius: 6)
      }
      HStack {
        Text(snapshot.mode)
        Spacer()
        Text(snapshot.isSilent ? tr("等待声音", "Waiting for speech") : tr("正在收音", "Listening"))
      }
      .font(.system(size: 10, weight: .medium)).foregroundStyle(SettingsTheme.hudForeground.opacity(0.6))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(snapshot.isSilent ? tr("正在录音，等待声音", "Recording, waiting for speech") : tr("正在录音，已收到声音", "Recording, receiving audio"))
  }

  private var processingStage: some View {
    let phases: [HUDPhase] = snapshot.phase == .preparing ? [.preparing]
      : snapshot.includesEditing ? [.transcribing, .processing, .delivering] : [.transcribing, .delivering]
    return HStack(spacing: 7) {
      ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
        if index > 0 { Capsule().fill(SettingsTheme.hudForeground.opacity(0.1)).frame(height: 1) }
        HStack(spacing: 5) {
          Circle().fill(phase == snapshot.phase ? tint : SettingsTheme.hudForeground.opacity(0.18)).frame(width: 5, height: 5)
          Text(stageTitle(phase)).font(.system(size: 10, weight: phase == snapshot.phase ? .semibold : .regular))
        }
        .foregroundStyle(phase == snapshot.phase ? SettingsTheme.hudForeground.opacity(0.95) : SettingsTheme.hudForeground.opacity(0.42))
      }
    }
    .padding(.horizontal, 11).frame(height: 34)
    .background(SettingsTheme.hudForeground.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityLabel(stageTitle(snapshot.phase))
  }

  @ViewBuilder private var actions: some View {
    if snapshot.phase.isBusy {
      Button(tr("取消", "Cancel"), action: onCancel).buttonStyle(HUDButtonStyle())
      if snapshot.phase == .recording {
        Button(action: onStop) { Label(tr("停止", "Stop"), systemImage: "stop.fill") }
          .buttonStyle(HUDButtonStyle(primary: true))
      } else if snapshot.phase == .selectingTarget {
        Button(snapshot.confirmTitle ?? tr("确认位置", "Confirm"), action: onConfirm).buttonStyle(HUDButtonStyle(primary: true))
      } else if snapshot.canUseOriginal {
        Button(tr("使用原文", "Use original"), action: onUseOriginal).buttonStyle(HUDButtonStyle(primary: true))
      }
    } else if snapshot.phase != .cancelled {
      if snapshot.phase == .failed {
        Button(tr("关闭", "Close"), action: onCancel).buttonStyle(HUDButtonStyle())
      }
      if snapshot.canRetry {
        Button(snapshot.retryTitle ?? tr("重试", "Retry"), action: onRetry).buttonStyle(HUDButtonStyle(primary: snapshot.settingsTitle == nil))
      }
      if let title = snapshot.settingsTitle {
        Button(title, action: onSettings).buttonStyle(HUDButtonStyle(primary: true))
      }
      if snapshot.canShowResult {
        Button(tr("查看结果", "View result"), action: onResult).buttonStyle(HUDButtonStyle())
      }
    }
  }

  private func stageTitle(_ phase: HUDPhase) -> String {
    switch phase {
    case .preparing: tr("准备录音", "Preparing")
    case .transcribing: tr("本地识别", "Transcribing")
    case .processing: tr("文字整理", "Editing")
    case .delivering: tr("输出", "Delivering")
    default: ""
    }
  }

  private func tr(_ zh: String, _ en: String) -> String { snapshot.isEnglish ? en : zh }
}

struct HUDScrollMetrics: Equatable {
  var offset: CGFloat
  var bottom: CGFloat
  var isAtBottom: Bool { bottom <= 0 || offset >= bottom - 12 }
}

private struct HUDButtonStyle: ButtonStyle {
  var primary = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(primary ? SettingsTheme.hudBackground : SettingsTheme.hudForeground.opacity(0.85))
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(primary ? SettingsTheme.leaf.opacity(configuration.isPressed ? 0.78 : 1)
                  : SettingsTheme.hudForeground.opacity(configuration.isPressed ? 0.13 : 0.06), in: Capsule())
      .contentShape(Capsule())
  }
}
