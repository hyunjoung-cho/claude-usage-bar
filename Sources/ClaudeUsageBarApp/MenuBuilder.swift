import AppKit
import ClaudeUsageBarCore

/// 우클릭 NSMenu를 빌드합니다. AppDelegate가 호출자.
@MainActor
final class MenuBuilder {
    /// AppDelegate에서 주입되는 콜백들.
    typealias Callbacks = (
        onRefresh:   () -> Void,
        onSelectSet: (String) -> Void,
        onSettings:  () -> Void,
        onQuit:      () -> Void
    )

    private var callbacks: Callbacks?
    private var selectSetMap: [ObjectIdentifier: String] = [:]   // NSMenuItem → set name
    private var refreshItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var openUsageItem: NSMenuItem?
    private var aboutItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var setItems: [NSMenuItem] = []

    func build(
        usage: UsageData?,
        sets: [IconSet],
        activeSet: String,
        onRefresh: @escaping () -> Void,
        onSelectSet: @escaping (String) -> Void,
        onSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        callbacks = (onRefresh, onSelectSet, onSettings, onQuit)
        selectSetMap.removeAll()
        setItems.removeAll()

        let menu = NSMenu()

        addUsageSection(to: menu, usage: usage)
        menu.addItem(.separator())
        addIconSetSection(to: menu, sets: sets, activeSet: activeSet)
        menu.addItem(.separator())
        addActionSection(to: menu)
        menu.addItem(.separator())
        addFooterSection(to: menu)

        return menu
    }

    // MARK: - 사용량 섹션

    private func addUsageSection(to menu: NSMenu, usage: UsageData?) {
        let header = NSMenuItem(title: "📊 사용량", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        guard let usage = usage else {
            let loading = NSMenuItem(title: "  로딩 중…", action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
            return
        }

        let fiveH = usage.fiveHourWindow
        let week  = usage.weeklyWindow
        let opus  = usage.opusWindow

        let fiveHLine = "  5h 세션 : \(fiveH.usedPercent)% (\(formatRelative(fiveH.resetsAt)) 남음)"
        let weekLine  = "  주간    : \(week.usedPercent)% (\(formatRelative(week.resetsAt)) 남음)"
        let opusLine  = "  Opus    : \(opus.usedPercent)%"

        for line in [fiveHLine, weekLine, opusLine] {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    /// "2h 14m" / "3d 8h" / "0m" 형식. 음수는 "0m"
    private func formatRelative(_ date: Date) -> String {
        let totalSec = max(0, Int(date.timeIntervalSinceNow))
        let d = totalSec / 86400
        let h = (totalSec % 86400) / 3600
        let m = (totalSec % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    // MARK: - 캐릭터셋 섹션

    private func addIconSetSection(to menu: NSMenu, sets: [IconSet], activeSet: String) {
        let header = NSMenuItem(title: "🎭 캐릭터셋", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if sets.isEmpty {
            let empty = NSMenuItem(title: "  (등록된 세트 없음)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for set in sets {
            let prefix = (set.name == activeSet) ? "● " : "○ "
            let item = NSMenuItem(
                title: "  " + prefix + set.name,
                action: #selector(handleSelectSet(_:)),
                keyEquivalent: ""
            )
            item.target = self
            selectSetMap[ObjectIdentifier(item)] = set.name
            setItems.append(item)
            menu.addItem(item)
        }
    }

    @objc private func handleSelectSet(_ sender: NSMenuItem) {
        guard let name = selectSetMap[ObjectIdentifier(sender)] else { return }
        callbacks?.onSelectSet(name)
    }

    // MARK: - 액션 섹션

    private func addActionSection(to menu: NSMenu) {
        let refresh = NSMenuItem(title: "🔄 지금 새로고침", action: #selector(handleRefresh), keyEquivalent: "r")
        refresh.target = self
        refreshItem = refresh
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "⚙️ 설정…", action: #selector(handleSettings), keyEquivalent: ",")
        settings.target = self
        settingsItem = settings
        menu.addItem(settings)

        let openUsage = NSMenuItem(title: "🌐 claude.ai/settings/usage 열기", action: #selector(handleOpenUsage), keyEquivalent: "")
        openUsage.target = self
        openUsageItem = openUsage
        menu.addItem(openUsage)
    }

    @objc private func handleRefresh() {
        callbacks?.onRefresh()
    }

    @objc private func handleSettings() {
        callbacks?.onSettings()
    }

    @objc private func handleOpenUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 푸터 섹션

    private func addFooterSection(to menu: NSMenu) {
        let about = NSMenuItem(title: "ℹ️ 정보", action: #selector(handleAbout), keyEquivalent: "")
        about.target = self
        aboutItem = about
        menu.addItem(about)

        let quit = NSMenuItem(title: "❌ 종료", action: #selector(handleQuit), keyEquivalent: "q")
        quit.target = self
        quitItem = quit
        menu.addItem(quit)
    }

    @objc private func handleAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func handleQuit() {
        callbacks?.onQuit()
    }
}
