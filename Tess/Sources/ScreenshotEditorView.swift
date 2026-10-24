import AppKit
import ImageIO
import SwiftUI

@MainActor
struct ScreenshotEditorView: View {
  let app: AppModel
  let imageURL: URL
  let onComplete: () -> Void
  let onCancel: () -> Void
  let selectionRect: CGRect
  let screenSize: CGSize
  let background: CGImage?

  private var canvasSize: CGSize { selectionRect.size }
  private var toolbarWidth: CGFloat { min(540, screenSize.width - 24) }
  private var hasStatusMessage: Bool { error != nil || app.storageNotice != nil || saved }
  private var toolbarOrigin: CGPoint {
    let height: CGFloat = hasStatusMessage ? 78 : 46
    let x = min(max(12, selectionRect.maxX - toolbarWidth), screenSize.width - toolbarWidth - 12)
    let y: CGFloat
    if selectionRect.maxY + 12 + height <= screenSize.height - 12 { y = selectionRect.maxY + 12 }
    else if selectionRect.minY - 12 - height >= 12 { y = selectionRect.minY - 12 - height }
    else { y = max(12, min(selectionRect.maxY - height - 12, screenSize.height - height - 12)) }
    return CGPoint(x: x, y: y)
  }

  private enum Tool { case rectangle, ellipse, text }
  private enum Ink: CaseIterable {
    case red, yellow, green, blue, black, white

    var color: NSColor {
      switch self {
      case .red: NSColor(srgbRed: 0.9, green: 0.12, blue: 0.16, alpha: 1)
      case .yellow: NSColor(srgbRed: 1, green: 0.75, blue: 0, alpha: 1)
      case .green: NSColor(srgbRed: 0.12, green: 0.65, blue: 0.3, alpha: 1)
      case .blue: NSColor(srgbRed: 0.1, green: 0.4, blue: 0.95, alpha: 1)
      case .black: .black
      case .white: .white
      }
    }

    var name: (String, String) {
      switch self {
      case .red: ("红色", "Red")
      case .yellow: ("黄色", "Yellow")
      case .green: ("绿色", "Green")
      case .blue: ("蓝色", "Blue")
      case .black: ("黑色", "Black")
      case .white: ("白色", "White")
      }
    }
  }
  private enum Mark {
    case shape(Tool, CGRect, CGFloat, Ink)
    case text(String, CGPoint, CGFloat, Ink)
  }
  @State private var tool = Tool.rectangle
  @State private var ink = Ink.red
  @State private var original: CGImage?
  @State private var preview: NSImage?
  @State private var marks: [Mark] = []
  @State private var shape: CGRect?
  @State private var textPoint: CGPoint?
  @State private var textSize: CGFloat = 20
  @State private var text = ""
  @State private var needsSave = false
  @State private var error: String?
  @State private var saved = false
  @State private var discarding = false
  @FocusState private var editingText: Bool

  private var imageSize: CGSize {
    CGSize(width: original?.width ?? 1, height: original?.height ?? 1)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      ScreenshotBackdropView(image: background, size: screenSize)
      canvas.offset(x: selectionRect.minX, y: selectionRect.minY)
      VStack(spacing: 6) {
        toolbar
        if hasStatusMessage { statusMessage }
      }.frame(width: toolbarWidth).offset(x: toolbarOrigin.x, y: toolbarOrigin.y)
    }.frame(width: screenSize.width, height: screenSize.height)
    .foregroundStyle(SettingsTheme.foreground)
    .preferredColorScheme(.light).tint(SettingsTheme.accent)
    .onAppear { if original == nil { load() } }
    .onChange(of: imageURL) { _, _ in load() }
    .onChange(of: tool) { _, _ in _ = commitText() }
    .onChange(of: editingText) { _, focused in if !focused { _ = commitText() } }
    .onExitCommand { cancel() }
    .onDisappear { discarding = true }
  }

  private var canvas: some View {
    ZStack(alignment: .topLeading) {
        if let preview {
          let scale = canvasSize.width / imageSize.width
          Image(nsImage: preview).resizable().frame(width: canvasSize.width, height: canvasSize.height)
            .contentShape(Rectangle()).gesture(drawing(scale: scale))
          if let shape {
            Path { path in
              let rect = CGRect(origin: .zero, size: CGSize(width: shape.width * scale, height: shape.height * scale))
              if tool == .rectangle { path.addRect(rect) } else { path.addEllipse(in: rect) }
            }.stroke(Color(nsColor: ink.color), lineWidth: 2.5)
              .frame(width: shape.width * scale, height: shape.height * scale)
              .offset(x: shape.minX * scale, y: shape.minY * scale)
              .allowsHitTesting(false)
          }
          if let textPoint {
            TextField(app.tr("输入文字，回车完成", "Type text, Return to finish"), text: $text)
              .textFieldStyle(.plain).font(.system(size: textSize * scale, weight: .semibold))
              .foregroundStyle(Color(nsColor: ink.color))
              .background(ink == .white ? Color.black.opacity(0.65) : Color.white.opacity(0.95))
              .frame(width: max(1, canvasSize.width - textPoint.x * scale), alignment: .leading)
              .offset(x: textPoint.x * scale, y: textPoint.y * scale)
              .focused($editingText).onSubmit { finish() }
          }
        }
      }.frame(width: canvasSize.width, height: canvasSize.height).clipped()
      .overlay(Rectangle().stroke(.white.opacity(0.8), lineWidth: 1).allowsHitTesting(false))
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
        Picker(app.tr("标注工具", "Annotation tool"), selection: $tool) {
          Label(app.tr("方框", "Box"), systemImage: "rectangle").tag(Tool.rectangle)
          Label(app.tr("圆圈", "Circle"), systemImage: "circle").tag(Tool.ellipse)
          Label(app.tr("文字", "Text"), systemImage: "textformat").tag(Tool.text)
        }.labelsHidden().labelStyle(.iconOnly).pickerStyle(.segmented).frame(width: 114)
        HStack(spacing: 4) {
          ForEach(Ink.allCases, id: \.self) { color in
            Button { ink = color } label: {
              Circle().fill(Color(nsColor: color.color))
                .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 1))
                .padding(3)
                .overlay(Circle().stroke(ink == color ? SettingsTheme.foreground : .clear, lineWidth: 1.5))
                .frame(width: 22, height: 22)
            }.buttonStyle(.plain).help(app.tr(color.name.0, color.name.1))
              .accessibilityLabel(app.tr(color.name.0, color.name.1))
          }
        }
        Divider().frame(height: 20)
        Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
          .disabled(marks.isEmpty && textPoint == nil)
          .keyboardShortcut(editingText ? nil : KeyboardShortcut("z", modifiers: .command))
          .help(app.tr("撤销 ⌘Z", "Undo ⌘Z"))
          .accessibilityLabel(app.tr("撤销", "Undo"))
        Button { save() } label: { Image(systemName: "square.and.arrow.down") }
          .disabled(original == nil)
          .keyboardShortcut("s", modifiers: .command)
          .help(app.tr("另存 PNG ⌘S", "Save PNG as… ⌘S"))
          .accessibilityLabel(app.tr("另存 PNG", "Save PNG as…"))
        Button { cancel() } label: { Image(systemName: "xmark") }
          .help(app.tr("取消 Esc", "Cancel Esc"))
          .accessibilityLabel(app.tr("取消", "Cancel"))
        Button { finish() } label: {
          Label(app.tr("完成", "Done"), systemImage: "checkmark")
        }.buttonStyle(.borderedProminent).keyboardShortcut(editingText ? nil : .defaultAction)
          .disabled(original == nil)
          .help(app.tr("完成并复制 ↵", "Finish and copy ↵"))
      }.buttonStyle(.borderless).controlSize(.regular)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: toolbarWidth, height: 46)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
  }

  private var statusMessage: some View {
    HStack(spacing: 8) {
        if let message = error ?? app.storageNotice {
          Text(message).lineLimit(1)
          Button(app.tr("重试", "Retry")) {
            if original == nil { load() }
            else if error != nil { _ = persist() }
            else { app.retryLocalSave() }
          }
        } else if saved {
          Text(app.tr("已保存图片", "Image saved"))
        }
      }.font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule()).frame(height: 26)
  }

  private func cancel() {
    discarding = true
    cancelText()
    onCancel()
  }

  private func load() {
    original = nil; preview = nil; marks = []; shape = nil
    cancelText(); needsSave = false; saved = false; discarding = false
    guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      error = app.tr("无法打开截图，请重试。", "Could not open the screenshot. Try again.")
      return
    }
    original = image
    preview = NSImage(cgImage: image, size: imageSize)
    error = nil
  }

  private func point(_ point: CGPoint, scale: CGFloat) -> CGPoint {
    CGPoint(x: min(max(0, point.x / scale), imageSize.width),
            y: min(max(0, point.y / scale), imageSize.height))
  }

  private func drawing(scale: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: tool == .text ? 0 : 2)
      .onChanged { value in
        guard tool != .text else { return }
        let start = point(value.startLocation, scale: scale), end = point(value.location, scale: scale)
        shape = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
      }
      .onEnded { value in
        if tool != .text {
          if let shape, shape.width * scale >= 2, shape.height * scale >= 2 {
            marks.append(.shape(tool, shape, 2.5 / scale, ink)); needsSave = true
            _ = updatePreview()
          }
          shape = nil
        } else {
          guard commitText() else { return }
          textSize = 20 / scale
          var location = point(value.startLocation, scale: scale)
          location.x = min(location.x, max(0, imageSize.width - textSize * 3))
          location.y = min(location.y, max(0, imageSize.height - textSize * 1.5))
          textPoint = location
          editingText = true
        }
      }
  }

  private func cancelText() {
    textPoint = nil; text = ""; editingText = false
  }

  @discardableResult private func commitText() -> Bool {
    guard !discarding else { return false }
    if let textPoint {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { marks.append(.text(value, textPoint, textSize, ink)); needsSave = true }
      cancelText()
    }
    return updatePreview()
  }

  private func undo() {
    if textPoint != nil { cancelText(); return }
    guard !marks.isEmpty else { return }
    marks.removeLast(); needsSave = true
    _ = updatePreview()
  }

  private func render() -> CGImage? {
    guard let original, let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: original.width, height: original.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(original, in: CGRect(origin: .zero, size: imageSize))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }
    for mark in marks {
      switch mark {
      case .shape(let tool, let rect, let width, let ink):
        context.setStrokeColor(ink.color.cgColor); context.setLineWidth(width)
        let bounds = CGRect(x: rect.minX, y: imageSize.height - rect.maxY, width: rect.width, height: rect.height)
        if tool == .rectangle { context.stroke(bounds) } else { context.strokeEllipse(in: bounds) }
      case .text(let value, let point, let size, let ink):
        let string = NSAttributedString(string: value, attributes: [
          .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: ink.color
        ])
        let width = max(1, imageSize.width - point.x)
        let height = min(imageSize.height - point.y,
                         ceil(string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
        string.draw(in: CGRect(x: point.x, y: imageSize.height - point.y - height,
                               width: width, height: height))
      }
    }
    return context.makeImage()
  }

  private func updatePreview() -> Bool {
    guard let image = render() else { return false }
    preview = NSImage(cgImage: image, size: imageSize)
    saved = false
    return true
  }

  private func persist() -> Bool {
    guard needsSave else { return original != nil }
    guard let image = render() else { return false }
    let bitmap = NSBitmapImageRep(cgImage: image)
    bitmap.size = canvasSize
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      error = app.tr("无法生成标注图片，请重试。", "Could not create the annotated image. Try again.")
      return false
    }
    preview = NSImage(cgImage: image, size: imageSize)
    guard app.capture.replaceImage(at: imageURL, pngData: data) else {
      error = app.capture.lastError ?? app.tr("保存标注失败，请重试。", "Could not save annotations. Try again.")
      return false
    }
    needsSave = false; error = nil; saved = false
    return true
  }

  private func finish() {
    guard commitText(), persist() else { return }
    guard app.capture.copyImage(imageURL) else {
      error = app.capture.lastError ?? app.tr("复制失败，请再次点击完成。", "Copy failed. Choose Done to retry.")
      return
    }
    onComplete()
  }

  private func save() {
    guard commitText(), persist(), let success = app.capture.saveImage(imageURL) else { return }
    saved = success
    error = success ? nil : app.capture.lastError ?? app.tr("保存失败，请重试。", "Save failed. Try again.")
  }
}

struct ScreenshotBackdropView: View {
  let image: CGImage?
  let size: CGSize

  var body: some View {
    ZStack {
      if let image { Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height) }
      Color.black.opacity(0.48)
    }.frame(width: size.width, height: size.height)
  }
}
