import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class CaptureService {
    enum Failure { case permissionRequired, captureFailed }
    private(set) var lastError: String?
    private(set) var failure: Failure?
    let capturesDirectory: URL
    private var captureID: UUID?
    @ObservationIgnored private var selectionController: ScreenshotSelectionController?
    @ObservationIgnored private(set) var placement: ScreenshotPlacement?
    @ObservationIgnored private var requestedScreenPermission = false

    init(capturesDirectory: URL) {
        self.capturesDirectory = capturesDirectory
    }

    func captureSelection() async -> URL? {
        guard captureID == nil else { return nil }
        releaseScreenSnapshots()
        placement = nil
        let id = UUID()
        captureID = id
        defer { if captureID == id { captureID = nil } }
        lastError = nil
        failure = nil
        guard !Task.isCancelled else { return nil }
        var allowed = CGPreflightScreenCaptureAccess()
        if !allowed, !requestedScreenPermission {
            requestedScreenPermission = true
            allowed = CGRequestScreenCaptureAccess()
        }
        guard allowed else {
            failure = .permissionRequired
            lastError = "请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Tess 截图。"
            return nil
        }
        guard !Task.isCancelled else { return nil }
        do {
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: capturesDirectory.path)
        } catch {
            failure = .captureFailed
            lastError = "无法创建 Tess 截图暂存目录。"
            return nil
        }
        do {
            let screens = try await ScreenshotSelectionController.captureScreens()
            guard captureID == id, !Task.isCancelled else { return nil }
            let selector = ScreenshotSelectionController()
            selectionController = selector
            let selected = await withTaskCancellationHandler {
                await selector.select(screens: screens)
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard self?.captureID == id else { return }
                    self?.cancel()
                }
            }
            guard captureID == id, !Task.isCancelled else { selector.dismiss(); return nil }
            guard let selected else { releaseScreenSnapshots(); return nil }
            let bitmap = NSBitmapImageRep(cgImage: selected.image)
            bitmap.size = selected.frame.size
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let url = capturesDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            do {
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                delete(url)
                throw error
            }
            placement = ScreenshotPlacement(imageURL: url, frame: selected.frame,
                                            screenFrame: selected.screenFrame, screens: screens)
            return url
        } catch {
            guard captureID == id, !Task.isCancelled else { return nil }
            releaseScreenSnapshots()
            failure = CGPreflightScreenCaptureAccess() ? .captureFailed : .permissionRequired
            lastError = failure == .permissionRequired
                ? "屏幕捕获权限不可用，请在系统设置中允许 Tess 后重试。"
                : "无法获取这张截图，请重试或检查屏幕捕获权限。"
            return nil
        }
    }

    func cancel() {
        captureID = nil
        releaseScreenSnapshots()
    }

    func releaseScreenSnapshots() {
        selectionController?.dismiss()
        selectionController = nil
        placement?.screens = []
    }

    @discardableResult
    func replaceImage(at url: URL, pngData: Data) -> Bool {
        lastError = nil
        guard isOwnedFile(url),
              let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let originalSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(originalSource, 0, nil),
              image.width == original.width, image.height == original.height else {
            lastError = "截图文件已不可用，或图片尺寸发生变化。"
            return false
        }
        do {
            try pngData.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            lastError = "无法保存标注，请重试。"
            return false
        }
    }

    @discardableResult
    func copyImage(_ url: URL) -> Bool {
        lastError = nil
        guard isOwnedFile(url), let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            lastError = "截图文件已不可用。"
            return false
        }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            lastError = "图片复制失败，请保存 PNG 后手动附加。"
            return false
        }
        return true
    }

    @discardableResult
    func saveImage(_ url: URL) -> Bool? {
        lastError = nil
        guard isOwnedFile(url), let data = try? Data(contentsOf: url) else {
            lastError = "截图文件已不可用。"
            return false
        }
        let panel = NSSavePanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Tess-\(Date.now.formatted(.iso8601.year().month().day())).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }
        do { try data.write(to: destination, options: .atomic); return true }
        catch { lastError = "保存 PNG 失败，请选择其他位置。"; return false }
    }

    func delete(_ url: URL) {
        guard owns(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func owns(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == capturesDirectory.standardizedFileURL
            && url.pathExtension == "png"
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }

    private func isOwnedFile(_ url: URL) -> Bool {
        guard owns(url), let metadata = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return metadata.isRegularFile == true && metadata.isSymbolicLink != true
    }
}
