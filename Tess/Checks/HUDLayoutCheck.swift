import AppKit
import SwiftUI

@main @MainActor struct HUDLayoutCheck {
    static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let text = "请检查 token、PRD 和 SwiftUI 的状态。This sentence keeps short English words together.\n保留段落以及 /tmp/long_project_name/requirements/PRD_document.json 的原始内容。"
        var heights: [CGFloat] = []
        for english in [false, true] {
            for count in [1, 3, 15] {
                for phase: HUDPhase in [.recording, .transcribing, .processing, .delivering, .copied] {
                    let snapshot = HUDSnapshot(phase: phase, title: english ? "Finalizing transcript" : "正在生成最终转录",
                                               subtitle: english ? "Live preview unavailable. Recording continues; the full audio will be transcribed when you stop." : "实时转录暂不可用，结束后将识别完整内容。",
                                               mode: "PRD · token", elapsed: 83, levels: [0.1, 0.4, 0.2], isEnglish: english,
                                               transcript: String(repeating: text, count: count), canUseOriginal: phase == .processing)
                    let host = NSHostingView(rootView: HUDView(snapshot: snapshot, previewReduceMotion: true).padding(16))
                    let size = host.fittingSize
                    precondition(size.width == 432 && size.height < 470, "HUD must fit the notebook prototype")
                    heights.append(size.height)
                    if count == 3, phase == .recording {
                        host.frame = CGRect(origin: .zero, size: size)
                        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                        window.contentView = host
                        host.layoutSubtreeIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                            host.cacheDisplay(in: host.bounds, to: bitmap)
                            try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(english ? "hud-en.png" : "hud-zh.png"))
                        }
                        window.orderOut(nil)
                    }
                }
            }
        }
        precondition(Set(heights).count == 1, "Text length, language and processing phase must not move the controls")
        precondition(HUDScrollMetrics(offset: 400, bottom: 400).isAtBottom)
        precondition(!HUDScrollMetrics(offset: 300, bottom: 400).isAtBottom)
        precondition(HUDScrollMetrics(offset: 0, bottom: -10).isAtBottom)
        print("HUD layout checks passed: 30 real SwiftUI layouts; Chinese/English, short/200+/1,000+ characters, stable \(heights[0])pt panel height, 432pt width, draft/final states and bottom geometry. Offscreen renders are not live scrolling or human acceptance.")
    }
}
