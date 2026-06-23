import AppKit
import ClaudeUsageBarCore

/// 우클릭 NSMenu를 빌드합니다. AppDelegate가 호출자.
@MainActor
final class MenuBuilder {
    /// AppDelegate에서 주입되는 콜백들.
    typealias Callbacks = (
        onRefresh:     () -> Void,
        onSelectSet:   (String) -> Void,
        onSelectSpeed: (Double) -> Void,
        onToggleMotion: (Bool) -> Void,
        onSettings:    () -> Void,
        onQuit:        () -> Void
    )

    private var callbacks: Callbacks?
    private var selectSetMap: [ObjectIdentifier: String] = [:]   // NSMenuItem → set name
    private var selectSpeedMap: [ObjectIdentifier: Double] = [:] // NSMenuItem → speed 배율
    private var motionMap: [ObjectIdentifier: Bool] = [:]        // NSMenuItem → 움직임 on/off
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
        thresholds: Thresholds = .default,    // NEW
        currentSpeed: Double = 2.0,           // NEW — 현재 GIF 속도 배율
        currentMotion: Bool = true,           // NEW — 현재 움직임 on/off
        onRefresh: @escaping () -> Void,
        onSelectSet: @escaping (String) -> Void,
        onSelectSpeed: @escaping (Double) -> Void = { _ in },
        onToggleMotion: @escaping (Bool) -> Void = { _ in },
        onSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        callbacks = (onRefresh, onSelectSet, onSelectSpeed, onToggleMotion, onSettings, onQuit)
        selectSetMap.removeAll()
        selectSpeedMap.removeAll()
        motionMap.removeAll()
        setItems.removeAll()

        let menu = NSMenu()

        addUsageSection(to: menu, usage: usage)
        menu.addItem(.separator())
        addIconSetSection(to: menu, sets: sets, activeSet: activeSet, thresholds: thresholds)
        menu.addItem(.separator())
        addSpeedSection(to: menu, currentSpeed: currentSpeed)
        menu.addItem(.separator())
        addMotionSection(to: menu, currentMotion: currentMotion)
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

    private func addIconSetSection(to menu: NSMenu, sets: [IconSet], activeSet: String, thresholds: Thresholds) {
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

            // 5단계 미리보기 submenu — 마우스 오버 시 자동 펼침
            item.submenu = buildPreviewSubmenu(for: set, thresholds: thresholds)

            menu.addItem(item)
        }
    }

    private func buildPreviewSubmenu(for set: IconSet, thresholds t: Thresholds) -> NSMenu {
        let menu = NSMenu()
        let stages: [(stage: Stage, range: String, label: String)] = [
            (.chill,  "0-\(t.chillMax)%",                  "여유"),
            (.normal, "\(t.chillMax)-\(t.normalMax)%",     "보통"),
            (.busy,   "\(t.normalMax)-\(t.busyMax)%",      "임박"),
            (.danger, "\(t.busyMax)-\(t.dangerMax)%",      "위험"),
            (.burn,   "\(t.dangerMax)-100%",               "불탐"),
        ]
        for (stage, range, label) in stages {
            let rangeLabel = "\(range.padding(toLength: 10, withPad: " ", startingAt: 0))\(label)"

            let item: NSMenuItem
            switch set.type {
            case .emoji:
                let glyph = set.value(for: stage)
                item = NSMenuItem(title: "\(glyph)   \(rangeLabel)", action: nil, keyEquivalent: "")
            case .png:
                // GIF/PNG 썸네일을 NSMenuItem.image로 (첫 프레임 정적)
                item = NSMenuItem(title: "   \(rangeLabel)", action: nil, keyEquivalent: "")
                if let folder = set.folderURL {
                    let path = folder.appendingPathComponent(set.value(for: stage))
                    if let img = NSImage(contentsOf: path) {
                        img.size = NSSize(width: 20, height: 20)
                        img.isTemplate = false
                        item.image = img
                    }
                }
            }
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    @objc private func handleSelectSet(_ sender: NSMenuItem) {
        guard let name = selectSetMap[ObjectIdentifier(sender)] else { return }
        callbacks?.onSelectSet(name)
    }

    // MARK: - 애니메이션 속도 섹션

    private func addSpeedSection(to menu: NSMenu, currentSpeed: Double) {
        let header = NSMenuItem(title: "🐢 움직임 속도", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // (배율, 라벨). 배율이 클수록 느림. 1.0 = 디자이너 원본.
        let options: [(speed: Double, label: String)] = [
            (1.0, "원본 (빠름)"),
            (2.0, "느리게"),
            (3.0, "더 느리게"),
            (4.0, "아주 느리게"),
        ]
        for (speed, label) in options {
            // 부동소수 비교 오차 방지: 0.1 이내면 현재 속도로 간주
            let isCurrent = abs(speed - currentSpeed) < 0.1
            let prefix = isCurrent ? "● " : "○ "
            let item = NSMenuItem(title: "  " + prefix + label, action: #selector(handleSelectSpeed(_:)), keyEquivalent: "")
            item.target = self
            selectSpeedMap[ObjectIdentifier(item)] = speed
            menu.addItem(item)
        }
    }

    @objc private func handleSelectSpeed(_ sender: NSMenuItem) {
        guard let speed = selectSpeedMap[ObjectIdentifier(sender)] else { return }
        callbacks?.onSelectSpeed(speed)
    }

    // MARK: - 부드럽게(움직임 on/off) 섹션

    private func addMotionSection(to menu: NSMenu, currentMotion: Bool) {
        let header = NSMenuItem(title: "✨ 부드럽게", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // 끊김이 거슬리면 "정지"로 = 움직임이 없으니 버벅임도 0.
        let options: [(on: Bool, label: String)] = [
            (true,  "움직임 켜기 (부드러운 애니메이션)"),
            (false, "정지 (끊김 완전 제거)"),
        ]
        for (on, label) in options {
            let prefix = (on == currentMotion) ? "● " : "○ "
            let item = NSMenuItem(title: "  " + prefix + label, action: #selector(handleSelectMotion(_:)), keyEquivalent: "")
            item.target = self
            motionMap[ObjectIdentifier(item)] = on
            menu.addItem(item)
        }
    }

    @objc private func handleSelectMotion(_ sender: NSMenuItem) {
        guard let on = motionMap[ObjectIdentifier(sender)] else { return }
        callbacks?.onToggleMotion(on)
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
