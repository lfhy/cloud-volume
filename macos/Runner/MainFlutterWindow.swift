import Cocoa
import desktop_multi_window
import FlutterMacOS

private let yunjuanDefaultWindowSize = NSSize(width: 1160, height: 740)
private let yunjuanMinimumWindowSize = NSSize(width: 920, height: 620)
private let yunjuanCompactFallbackSize = NSSize(width: 840, height: 560)

func yunjuanMainWindow() -> NSWindow? {
  NSApp.windows.first { $0 is MainFlutterWindow } ?? NSApp.mainWindow ?? NSApp.windows.first
}

func showYunjuanMainWindow() {
  guard let window = yunjuanMainWindow() else {
    return
  }
  if window.isMiniaturized {
    window.deminiaturize(nil)
  }
  NSApp.activate(ignoringOtherApps: true)
  window.makeKeyAndOrderFront(nil)
}

func hideYunjuanMainWindow() {
  yunjuanMainWindow()?.orderOut(nil)
}

// MenuBarController owns the macOS tray item so it survives as long as the
// main window object lives, mirroring the proven CloudPlayer setup.
final class MenuBarController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = NSMenu()

  override init() {
    super.init()
    configureStatusItem()
    configureMenu()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else {
      return
    }
    button.toolTip = "云卷"
    button.imageScaling = .scaleProportionallyDown
    button.imagePosition = .imageOnly
    button.title = ""
    button.target = self
    button.action = #selector(handleStatusItemPressed(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    if let image = makeTrayStatusImage() {
      button.image = image
    } else if let image = NSApp.applicationIconImage.copy() as? NSImage {
      image.isTemplate = true
      image.size = NSSize(width: 22, height: 21)
      button.image = image
    }
  }

  private func makeTrayStatusImage() -> NSImage? {
    guard let image = NSImage(named: "TrayIcon")?.copy() as? NSImage else {
      return nil
    }
    // Keep tray rendering simple and deterministic: use the prebuilt transparent
    // template asset instead of reshaping the app icon at runtime.
    image.isTemplate = true
    image.size = NSSize(width: 22, height: 21)
    return image
  }

  private func configureMenu() {
    let showItem = NSMenuItem(title: "显示主窗口", action: #selector(handleShowMainWindow), keyEquivalent: "")
    showItem.target = self
    let hideItem = NSMenuItem(title: "隐藏到托盘", action: #selector(handleHideMainWindow), keyEquivalent: "")
    hideItem.target = self
    let quitItem = NSMenuItem(title: "退出云卷", action: #selector(handleTerminate), keyEquivalent: "q")
    quitItem.target = self

    menu.autoenablesItems = false
    menu.items = [
      showItem,
      hideItem,
      .separator(),
      quitItem,
    ]
  }

  @objc private func handleStatusItemPressed(_ sender: NSStatusBarButton) {
    menu.popUp(
      positioning: nil,
      at: NSPoint(x: 0, y: sender.bounds.maxY + 6),
      in: sender
    )
  }

  @objc private func handleShowMainWindow() {
    showYunjuanMainWindow()
  }

  @objc private func handleHideMainWindow() {
    hideYunjuanMainWindow()
  }

  @objc private func handleTerminate() {
    if let window = yunjuanMainWindow() as? MainFlutterWindow {
      window.terminateWithoutConfirmation()
      return
    }
    NSApp.terminate(nil)
  }
}

// MainFlutterWindow keeps the macOS host chrome thin and owns the menu-bar
// controller so tray behavior stays alive across window show/hide cycles.
class MainFlutterWindow: NSWindow {
  private var menuBarController: MenuBarController?
  private var allowsDirectClose = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.toolbar = nil
    self.isReleasedWhenClosed = false
    self.minSize = yunjuanMinimumWindowSize
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      // Secondary preview windows run in their own engine, so plugins must be
      // registered for each created controller as well as the main one.
      RegisterGeneratedPlugins(registry: controller)
    }
    menuBarController = MenuBarController()

    super.awakeFromNib()

    // Always reopen at the product default size instead of reusing the last
    // window dimensions from a previous app launch.
    DispatchQueue.main.async { [weak self] in
      self?.applyDefaultWindowLayout()
    }
  }

  private func applyDefaultWindowLayout() {
    let targetSize = resolvedInitialWindowSize()
    self.minSize = NSSize(
      width: min(yunjuanMinimumWindowSize.width, targetSize.width),
      height: min(yunjuanMinimumWindowSize.height, targetSize.height)
    )
    let targetFrame = centeredWindowFrame(for: targetSize)
    self.setFrame(targetFrame, display: true)
  }

  // macOS should follow the same small-screen behavior as Linux so the first
  // window fits lower-resolution laptops without relying on manual resize.
  private func resolvedInitialWindowSize() -> NSSize {
    let visibleFrame = (self.screen ?? NSScreen.main)?.visibleFrame ?? self.frame
    let width = resolvedDimension(
      available: visibleFrame.width,
      defaultValue: yunjuanDefaultWindowSize.width,
      minimumValue: yunjuanMinimumWindowSize.width,
      fallbackValue: yunjuanCompactFallbackSize.width,
      scale: 0.72
    )
    let height = resolvedDimension(
      available: visibleFrame.height,
      defaultValue: yunjuanDefaultWindowSize.height,
      minimumValue: yunjuanMinimumWindowSize.height,
      fallbackValue: yunjuanCompactFallbackSize.height,
      scale: 0.66
    )
    return NSSize(width: width, height: height)
  }

  private func resolvedDimension(
    available: CGFloat,
    defaultValue: CGFloat,
    minimumValue: CGFloat,
    fallbackValue: CGFloat,
    scale: CGFloat
  ) -> CGFloat {
    let fittedMinimum = min(minimumValue, max(fallbackValue, available - 32))
    let fittedMaximum = min(defaultValue, max(fittedMinimum, available * scale))
    return max(fittedMinimum, fittedMaximum)
  }

  private func centeredWindowFrame(for size: NSSize) -> NSRect {
    let referenceScreen = self.screen ?? NSScreen.main
    let visibleFrame = referenceScreen?.visibleFrame ?? self.frame
    let originX = visibleFrame.origin.x + ((visibleFrame.width - size.width) / 2)
    let originY = visibleFrame.origin.y + ((visibleFrame.height - size.height) / 2)
    return NSRect(origin: NSPoint(x: originX, y: originY), size: size)
  }

  fileprivate func terminateWithoutConfirmation() {
    allowsDirectClose = true
    NSApp.terminate(nil)
  }

  override func close() {
    if allowsDirectClose {
      super.close()
      return
    }
    confirmCloseRequest()
  }

  fileprivate func confirmCloseRequest() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "退出云卷？"
    alert.informativeText = "你可以直接退出应用，也可以隐藏到托盘后继续在后台保留。"
    alert.addButton(withTitle: "退出云卷")
    alert.addButton(withTitle: "隐藏到托盘")
    alert.addButton(withTitle: "取消")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      terminateWithoutConfirmation()
      return
    }
    if response == .alertSecondButtonReturn {
      hideYunjuanMainWindow()
    }
  }
}

extension MainFlutterWindow: NSWindowDelegate {
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if allowsDirectClose {
      return true
    }
    confirmCloseRequest()
    return false
  }
}
