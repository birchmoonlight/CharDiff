import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?

    private struct LaunchOptions {
        var fontA: URL?
        var fontB: URL?
        var text: String?
        var exportPath: String?
        var overlay = false
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
        let controller = MainViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "字体字符对比"
        window.contentViewController = controller
        controller.applyLaunchOptions(fontA: launch.fontA,
                                      fontB: launch.fontB,
                                      text: launch.text,
                                      overlay: launch.overlay)
        window.setFrameAutosaveName("FontCompareWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        if let path = launch.exportPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                controller.exportSnapshot(to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
