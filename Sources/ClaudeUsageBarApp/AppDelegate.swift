import AppKit
import SwiftUI
import ClaudeUsageBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var configStore: ConfigStore!
    private var keyManager:  SessionKeyManager!
    private var loader:      IconSetLoader!
    private var poller:      UsagePoller!
    private var engine:      AnimationEngine!
    private var menuBuilder: MenuBuilder!

    private var config: Config = .default
    private var sets:   [IconSet] = []

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrap()
        ensureDefaultSetsInstalled()
        loadStartup()
        startPolling()
    }

    @MainActor
    private func bootstrap() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configStore = ConfigStore(url: ConfigStore.defaultURL)
        keyManager  = SessionKeyManager()
        loader      = IconSetLoader(rootURL: IconSetLoader.defaultRootURL)
        engine      = AnimationEngine()
        engine.statusItem = statusItem
        poller = UsagePoller(scanner: UsageScanner(), limits: .pro)
        // UsagePoller 콜백은 임의 스레드에서 호출 → MainActor 홉
        poller.onUpdate = { [weak self] usage in
            Task { @MainActor in self?.handleUpdate(usage) }
        }
        poller.onError = { [weak self] err in
            Task { @MainActor in self?.handleError(err) }
        }
        menuBuilder = MenuBuilder()
    }

    /// 첫 실행 시 번들된 default-sets 폴더들을 Application Support로 복사합니다.
    /// 이미 존재하는 폴더는 덮어쓰지 않습니다.
    private func ensureDefaultSetsInstalled() {
        let root = IconSetLoader.defaultRootURL
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let bundleSetsURL = Bundle.main.url(forResource: "default-sets", withExtension: nil) else {
            NSLog("[ClaudeUsageBar] default-sets bundle resource not found — skipping copy")
            return
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: bundleSetsURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for entry in entries {
            let target = root.appendingPathComponent(entry.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.copyItem(at: entry, to: target)
            }
        }
    }

    @MainActor
    private func loadStartup() {
        config = (try? configStore.load()) ?? .default
        sets   = loader.loadAll()
        let activeSet = sets.first { $0.name == config.activeSet } ?? sets.first
        engine.use(thresholds: config.thresholds)
        engine.use(showPercent: config.showPercentInMenubar, showTimeLeft: config.showTimeLeftInMenubar)
        if let s = activeSet { engine.use(set: s) }
        poller.limits = config.effectiveLimits     // NEW — 디스크에서 로드한 config의 plan 반영
        engine.showStatus(text: "loading…")
        rebuildMenu()
    }

    @MainActor
    private func startPolling() {
        poller.start(intervalSec: config.pollIntervalSec)
    }

    @MainActor
    private func handleUpdate(_ usage: UsageData) {
        let pct = usage.fiveHourWindow.usedPercent
        let leftSec = max(0, Int(usage.fiveHourWindow.resetsAt.timeIntervalSinceNow))
        engine.update(percent: pct, timeLeftSec: leftSec)
        rebuildMenu(usage: usage)
    }

    @MainActor
    private func handleError(_ err: PollError) {
        switch err {
        case .noClaudeData:
            engine.showStatus(text: "📂 데이터 없음")
        case .ioError:
            engine.showStatus(text: "🔌 IO")
        case .parseError:
            engine.showStatus(text: "❓ 파싱")
        }
        rebuildMenu()
    }

    @MainActor
    private func rebuildMenu(usage: UsageData? = nil) {
        let menu = menuBuilder.build(
            usage: usage,
            sets: sets,
            activeSet: config.activeSet,
            thresholds: config.thresholds,         // NEW
            onRefresh: { [weak self] in self?.handleRefresh() },
            onSelectSet: { [weak self] name in self?.handleSelectSet(name) },
            onSettings: { [weak self] in
                guard let self = self else { return }
                SettingsView.present(
                    current: self.config,
                    onSave: { [weak self] updated in
                        self?.handleConfigSave(updated)
                    }
                )
            },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        statusItem.menu = menu
    }

    @MainActor
    private func handleRefresh() {
        poller.start(intervalSec: config.pollIntervalSec)
    }

    @MainActor
    private func handleSelectSet(_ name: String) {
        config.activeSet = name
        try? configStore.save(config)
        if let s = sets.first(where: { $0.name == name }) {
            engine.use(set: s)
        }
        rebuildMenu()
    }

    @MainActor
    private func handleConfigSave(_ updated: Config) {
        self.config = updated
        try? configStore.save(updated)
        engine.use(thresholds: updated.thresholds)
        engine.use(showPercent: updated.showPercentInMenubar, showTimeLeft: updated.showTimeLeftInMenubar)
        poller.limits = updated.effectiveLimits     // NEW — plan 변경 즉시 반영
        // 다음 폴링부터 새 주기 적용
        poller.start(intervalSec: updated.pollIntervalSec)
        rebuildMenu()
    }

    @MainActor
    private func handleResetSessionKey() {
        keyManager.delete()
        poller.stop()
        engine.showStatus(text: "⚠ 세션키 등록")
        SessionKeyEntryView.present { [weak self] key in
            try? self?.keyManager.save(key)
            self?.poller.start(intervalSec: self?.config.pollIntervalSec ?? 60)
        }
    }
}
