import AppKit
import SwiftUI

@main
enum TessApplication {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = TessAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(delegate) {}
  }
}

@MainActor final class TessAppDelegate: NSObject, NSApplicationDelegate {
  private var model: AppModel!
  private var statusItem: NSStatusItem!
  private var menuBarIcon: TessMenuBarIconHost?
  private var resultWindow: NSWindow?
  private var screenshotWindow: ScreenshotWindow?
  private var screenshotDimmingWindows: [NSWindow] = []
  private var settingsWindow: NSWindow?
  private var hud: HUDWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    TessBrand.registerFonts()
    #if TESS_INTERNAL_CHECKS
    if CommandLine.arguments.contains("--smoke-test") {
      guard let directory = ProcessInfo.processInfo.environment["TESS_DATA_DIRECTORY"],
            directory.hasPrefix("/"),
            URL(fileURLWithPath: directory).standardizedFileURL != FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tess").standardizedFileURL else {
        print("Smoke checks require an explicit isolated TESS_DATA_DIRECTORY.")
        exit(2)
      }
    }
    if CommandLine.arguments.contains("--asr-benchmark") {
      Task { exit(await ASRBenchmark.runFromEnvironment()) }
      return
    }
    if CommandLine.arguments.contains("--hud-preview") {
      settingsWindow = window(title: "Tess · 隔离原生动效预览", size: NSSize(width: 700, height: 720))
      let view = NSHostingView(rootView: HUDPreviewCard(autoplay: ProcessInfo.processInfo.environment["TESS_PREVIEW_AUTOPLAY"] == "1"))
      view.sizingOptions = []
      settingsWindow?.contentView = view
      settingsWindow?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      return
    }
    #endif
    if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "life.baode.tess")
      .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
      existing.activate(options: [])
      NSApplication.shared.terminate(nil)
      return
    }
    model = AppModel()
    installEditingMenu()
    model.openResult = { [weak self] in self?.openResult() }
    model.openSettings = { [weak self] in self?.openSettings() }
    model.showHUD = { [weak self] in self?.showHUD() }
    model.hideHUD = { [weak self] in self?.hud?.hide() }
    model.hideHUDImmediately = { [weak self] in self?.hud?.hide(immediately: true) }
    model.hideWindows = { [weak self] in
      self?.resultWindow?.orderOut(nil); self?.settingsWindow?.orderOut(nil)
      self?.closeScreenshotEditor()
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      let icon = TessMenuBarIconHost(app: model)
      icon.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(icon)
      NSLayoutConstraint.activate([
        icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
        icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        icon.widthAnchor.constraint(equalToConstant: 22),
        icon.heightAnchor.constraint(equalToConstant: 22)
      ])
      menuBarIcon = icon
    }
    statusItem.button?.toolTip = "Tess · " + model.tr("苔丝", "Voice input")
    statusItem.button?.setAccessibilityLabel("Tess")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(openMenu)
    #if TESS_INTERNAL_CHECKS
    if CommandLine.arguments.contains("--smoke-test") {
      let preview = ProcessInfo.processInfo.environment["TESS_PREVIEW_SCREEN"] ?? "result"
      if preview == "settings" {
        model.settingsSection = .about
        openSettings()
      } else if preview == "hud" {
        model.status = model.tr("隔离显示检查 · 未开始录音", "Isolated display check · Not recording")
        showHUD()
      } else if preview == "capture-permission" {
        model.finishCaptureFailure(.permissionRequired)
      } else if preview == "menubar" {
        // The isolated check renders only Tess's own status button.
      } else { openResult() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self else { return }
        let window = preview == "settings" ? self.settingsWindow : ["hud", "capture-permission"].contains(preview) ? self.hud?.window : self.resultWindow
        if preview == "menubar", let button = self.statusItem.button {
          let center = NSPoint(x: button.frame.midX, y: button.frame.midY)
          precondition(button.hitTest(center) === button, "The animated icon must leave menu clicks on the original button")
          precondition(self.menuBarIcon?.acceptsFirstResponder == false)
          print("Tess status button hit testing and non-focus behavior passed.")
        }
        let view: NSView? = preview == "menubar" ? self.statusItem.button : window?.contentView
        if let path = ProcessInfo.processInfo.environment["TESS_PREVIEW_PATH"], let view,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
          view.cacheDisplay(in: view.bounds, to: bitmap)
          try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        NSApplication.shared.terminate(nil)
      }
    } else if !model.preferences.completedOnboarding { openResult() }
    #else
    if !model.preferences.completedOnboarding { openResult() }
    #endif
  }

  func applicationWillTerminate(_ notification: Notification) { model?.shutdown(); hud?.hide(immediately: true); menuBarIcon?.stop() }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    #if TESS_INTERNAL_CHECKS
    return CommandLine.arguments.contains("--hud-preview")
    #else
    return false
    #endif
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard model != nil else { return false }
    if model.preferences.completedOnboarding { openSettings() } else { openResult() }
    return true
  }

  private func installEditingMenu() {
    let main = NSMenu()
    let applicationItem = NSMenuItem()
    let application = NSMenu(title: "Tess")
    application.addItem(withTitle: model.tr("退出 Tess", "Quit Tess"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    applicationItem.submenu = application
    main.addItem(applicationItem)
    let editItem = NSMenuItem(title: model.tr("编辑", "Edit"), action: nil, keyEquivalent: "")
    let edit = NSMenu(title: editItem.title)
    edit.addItem(withTitle: model.tr("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: model.tr("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: model.tr("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: model.tr("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: model.tr("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: model.tr("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)
    NSApplication.shared.mainMenu = main
  }

  @objc private func openMenu() {
    let menu = NSMenu()
    func item(_ title: String, _ selector: Selector) {
      let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
      entry.target = self; menu.addItem(entry)
    }
    item(model.isRecording ? model.tr("停止录音", "Stop recording") : model.tr("开始录音", "Start recording"), #selector(toggleRecording))
    item(model.tr("选区截图", "Capture selection"), #selector(screenshot))
    item(model.tr("最近结果", "Latest result"), #selector(openResult))
    item(model.tr("粘贴文字整理", "Edit pasted text"), #selector(manualText))
    menu.addItem(.separator())
    let modeMenu = NSMenu()
    for (index, mode) in TextMode.allCases.enumerated() {
      let entry = NSMenuItem(title: model.modeTitle(mode), action: #selector(changeMode(_:)), keyEquivalent: "")
      entry.tag = index; entry.target = self; entry.state = model.preferences.textMode == mode ? .on : .off
      entry.isEnabled = mode == .raw || model.configurations.current?.testStatus == .passed
      modeMenu.addItem(entry)
    }
    let entry = NSMenuItem(title: model.tr("整理模式", "Text mode"), action: nil, keyEquivalent: "")
    entry.submenu = modeMenu; menu.addItem(entry)
    menu.addItem(.separator())
    if !model.preferences.completedOnboarding { item(model.tr("继续设置 Tess…", "Continue setup…"), #selector(openResult)) }
    item(model.tr("设置…", "Settings…"), #selector(openSettings))
    item(model.tr("退出 Tess", "Quit Tess"), #selector(quit))
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }
  @objc private func changeMode(_ sender: NSMenuItem) {
    model.preferences.textMode = TextMode.allCases[sender.tag]; model.savePreferences()
  }
  @objc private func toggleRecording() { model.isRecording ? model.stopRecording() : model.startRecording() }
  @objc private func screenshot() { model.takeScreenshot() }
  @objc private func manualText() { model.newText() }
  @objc private func quit() { NSApplication.shared.terminate(nil) }

  @objc private func openResult() {
    if !model.showingManualInput, model.isImageOnlyResult, let url = model.imageURL {
      openScreenshotEditor(url)
      return
    }
    closeScreenshotEditor()
    if resultWindow == nil {
      resultWindow = window(title: "Tess · " + model.tr("最近结果", "Latest result"), size: NSSize(width: 760, height: 690))
      let view = NSHostingView(rootView: ResultView(app: model))
      view.sizingOptions = []
      resultWindow?.contentView = view
    }
    resultWindow?.title = "Tess · " + model.tr("最近结果", "Latest result")
    resultWindow?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  private func openScreenshotEditor(_ url: URL) {
    if let window = screenshotWindow, window.representedURL == url {
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      return
    }
    let placement = model.capture.placement.flatMap { $0.imageURL == url ? $0 : nil }
    hideScreenshotWindows()
    resultWindow?.orderOut(nil)
    guard let screen = NSScreen.screens.first(where: { $0.frame == placement?.screenFrame })
      ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
      model.capture.releaseScreenSnapshots()
      return
    }
    let selection: CGRect
    if let placement, placement.screenFrame == screen.frame {
      selection = placement.frame
    } else {
      let available = screen.visibleFrame.insetBy(dx: 20, dy: 20)
      let imageSize = NSImage(contentsOf: url)?.size ?? NSSize(width: 480, height: 320)
      let scale = min(1, available.width / max(1, imageSize.width), available.height / max(1, imageSize.height))
      let size = NSSize(width: max(1, imageSize.width * scale), height: max(1, imageSize.height * scale))
      selection = NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                         width: size.width, height: size.height)
    }
    for other in NSScreen.screens where other != screen {
      let dimmer = FloatingPanel(contentRect: other.frame, styleMask: .borderless, backing: .buffered, defer: false)
      dimmer.backgroundColor = .clear
      dimmer.isOpaque = false
      dimmer.hasShadow = false
      dimmer.isReleasedWhenClosed = false
      dimmer.level = .screenSaver
      dimmer.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      let view = NSHostingView(rootView: ScreenshotBackdropView(
        image: placement?.screens.first(where: { $0.frame == other.frame })?.image, size: other.frame.size))
      view.sizingOptions = []
      dimmer.contentView = view
      screenshotDimmingWindows.append(dimmer)
      dimmer.orderFrontRegardless()
    }
    let window = ScreenshotWindow(frame: screen.frame, onCancel: { [weak self] in self?.closeScreenshotEditor() })
    window.representedURL = url
    let rect = CGRect(x: selection.minX - screen.frame.minX, y: screen.frame.maxY - selection.maxY,
                      width: selection.width, height: selection.height)
    let view = NSHostingView(rootView: ScreenshotEditorView(app: model, imageURL: url,
      onComplete: model.completeScreenshotEditing, onCancel: { [weak self] in self?.closeScreenshotEditor() },
      selectionRect: rect, screenSize: screen.frame.size,
      background: placement?.screens.first(where: { $0.frame == screen.frame })?.image))
    view.sizingOptions = []
    window.contentView = view
    screenshotWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    model.capture.releaseScreenSnapshots()
  }

  private func hideScreenshotWindows() {
    screenshotWindow?.orderOut(nil)
    screenshotWindow?.contentView = nil
    screenshotWindow = nil
    for window in screenshotDimmingWindows { window.orderOut(nil); window.contentView = nil }
    screenshotDimmingWindows = []
  }

  private func closeScreenshotEditor() {
    hideScreenshotWindows()
    model?.capture.releaseScreenSnapshots()
  }

  func applicationDidResignActive(_ notification: Notification) {
    model?.capture.cancel()
    closeScreenshotEditor()
  }

  @objc private func openSettings() {
    if settingsWindow == nil {
      settingsWindow = window(title: "Tess · " + model.tr("设置", "Settings"), size: NSSize(width: 940, height: 730))
      let view = NSHostingView(rootView: SettingsView(app: model))
      view.sizingOptions = []
      settingsWindow?.contentView = view
      settingsWindow?.minSize = NSSize(width: 850, height: 660)
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
  private func window(title: String, size: NSSize) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = title
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = SettingsTheme.backgroundColor
    window.appearance = NSAppearance(named: .aqua)
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: size.width - 80, height: 560)
    window.center()
    return window
  }
  private func showHUD() {
    guard !model.isPracticing else { return }
    if hud == nil { hud = HUDWindowController() }
    hud?.show(app: model)
  }
}

final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

