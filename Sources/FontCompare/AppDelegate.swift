import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var window: NSWindow?

    /// 与 MainViewController 用同一个 suite。
    private let settings = UserDefaults(suiteName: "local.fontcompare") ?? .standard

    private struct LaunchOptions {
        var fontA: URL?
        var fontB: URL?
        var text: String?
        var exportPath: String?
        var overlay = false
        var dark = false
    }

    private let launch = AppDelegate.parseArguments()

    private static func parseArguments() -> LaunchOptions {
        var options = LaunchOptions()
        let args = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < args.count {
            let value = index + 1 < args.count ? args[index + 1] : nil
            switch args[index] {
            case "--a", "-a":
                if let value { options.fontA = URL(fileURLWithPath: value); index += 1 }
            case "--b", "-b":
                if let value { options.fontB = URL(fileURLWithPath: value); index += 1 }
            case "--text", "-t":
                if let value { options.text = value; index += 1 }
            case "--export", "-e":
                if let value { options.exportPath = value; index += 1 }
            case "--overlay":
                options.overlay = true
            case "--dark":
                options.dark = true
            default:
                break
            }
            index += 1
        }
        return options
    }

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于字体字符对比",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        // 没有「编辑」菜单，⌘C/⌘V/⌘A 就不会被分发到输入框——macOS 的快捷键是走菜单的。
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销",
                         action: Selector(("undo:")),
                         keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做",
                         action: Selector(("redo:")),
                         keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切",
                         action: #selector(NSText.cut(_:)),
                         keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝",
                         action: #selector(NSText.copy(_:)),
                         keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴",
                         action: #selector(NSText.paste(_:)),
                         keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选",
                         action: #selector(NSText.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        if launch.dark {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        let controller = MainViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "字体字符对比"
        window.minSize = NSSize(width: 1040, height: 480)
        window.contentViewController = controller
        controller.applyLaunchOptions(fontA: launch.fontA,
                                      fontB: launch.fontB,
                                      text: launch.text,
                                      overlay: launch.overlay)
        window.delegate = self

        // 恢复上次的位置和大小，位置失效（比如显示器拔了）就回到屏幕中央。
        if let saved = settings.string(forKey: "windowFrame") {
            let frame = NSRectFromString(saved)
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
            if onScreen && frame.width > 300 && frame.height > 200 {
                window.setFrame(frame, display: false)
            } else {
                window.center()
            }
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        if let path = launch.exportPath {
            exportWhenReady(controller, to: URL(fileURLWithPath: path), waited: 0)
        }
    }

    /// 长文本是后台排版的，等它排完再导，不然截到的是空画布。
    private func exportWhenReady(_ controller: MainViewController, to url: URL, waited: TimeInterval) {
        let deadline: TimeInterval = 20
        if (waited > 0.8 && controller.isCompareIdle) || waited > deadline {
            controller.exportSnapshot(to: url)
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.exportWhenReady(controller, to: url, waited: waited + 0.2)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 窗口位置

    func windowDidMove(_ notification: Notification) { saveWindowFrame() }
    func windowDidResize(_ notification: Notification) { saveWindowFrame() }

    private func saveWindowFrame() {
        guard let window else { return }
        settings.set(NSStringFromRect(window.frame), forKey: "windowFrame")
        // 退出前如果只移动过一次、还没落盘，这里保证写下去。
        settings.synchronize()
    }
}
