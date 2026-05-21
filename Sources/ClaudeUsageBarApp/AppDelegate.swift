import AppKit
import ClaudeUsageBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🌟 hello"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
