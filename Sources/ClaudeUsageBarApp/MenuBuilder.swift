import AppKit
import ClaudeUsageBarCore

/// T13에서 사용량 섹션 + 캐릭터셋 라디오 그룹 + 설정/링크/정보 메뉴를 추가합니다.
/// 현재(T12)는 최소 quit 메뉴만 제공해 앱이 종료될 수 있도록 합니다.
final class MenuBuilder {
    @MainActor
    func build(
        usage: UsageData?,
        sets: [IconSet],
        activeSet: String,
        onRefresh: @escaping () -> Void,
        onSelectSet: @escaping (String) -> Void,
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        // 사용량 placeholder (T13 본격 구현)
        if let usage = usage {
            let pct = usage.fiveHourWindow.usedPercent
            menu.addItem(NSMenuItem(title: "5h 세션 : \(pct)%", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "사용량 : 로딩 중…", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())

        // 캐릭터셋 placeholder (T13 라디오 그룹으로 교체)
        for set in sets {
            let title = (set.name == activeSet ? "● " : "○ ") + set.name
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            // 캐릭터셋 클릭은 T13에서 제대로 연결. 지금은 빈 동작.
            menu.addItem(item)
        }
        _ = onSelectSet   // T13에서 연결

        if !sets.isEmpty { menu.addItem(.separator()) }

        let refresh = NSMenuItem(title: "🔄 지금 새로고침", action: #selector(MenuBuilder.handleRefresh(_:)), keyEquivalent: "r")
        refresh.target = self
        self.onRefreshClosure = onRefresh
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "❌ 종료", action: #selector(MenuBuilder.handleQuit(_:)), keyEquivalent: "q")
        quit.target = self
        self.onQuitClosure = onQuit
        menu.addItem(quit)

        return menu
    }

    private var onRefreshClosure: (() -> Void)?
    private var onQuitClosure: (() -> Void)?

    @objc private func handleRefresh(_ sender: NSMenuItem) {
        onRefreshClosure?()
    }

    @objc private func handleQuit(_ sender: NSMenuItem) {
        onQuitClosure?()
    }
}
