import AppKit
import ClaudeUsageBarCore

@MainActor
final class AnimationEngine {
    weak var statusItem: NSStatusItem?
    private(set) var currentSet: IconSet?
    private(set) var currentStage: Stage = .chill

    private var animationTimer: Timer?
    private var jumpOffset: CGFloat = 0
    private var thresholds: Thresholds = .default
    private var showPercent = true
    private var showTimeLeft = true
    private var lastPercent: Int = 0
    private var lastTimeLeftSec: Int = 0

    func use(set: IconSet) {
        self.currentSet = set
        renderText(percent: lastPercent, timeLeftSec: lastTimeLeftSec)
        renderIcon()
    }

    func use(thresholds: Thresholds) {
        self.thresholds = thresholds
    }

    func use(showPercent: Bool, showTimeLeft: Bool) {
        self.showPercent = showPercent
        self.showTimeLeft = showTimeLeft
    }

    func update(percent: Int, timeLeftSec: Int) {
        self.lastPercent = percent
        self.lastTimeLeftSec = timeLeftSec

        let stage = Stage.from(percent: percent, thresholds: thresholds)
        if stage != currentStage {
            currentStage = stage
            restartAnimationTimer()
        }
        renderText(percent: percent, timeLeftSec: timeLeftSec)
        renderIcon()
    }

    /// 임시 상태 메시지(로딩/에러 등)를 표시합니다. 아이콘은 지웁니다.
    func showStatus(text: String) {
        statusItem?.button?.title = text
        statusItem?.button?.image = nil
        statusItem?.button?.attributedTitle = NSAttributedString(string: text)
    }

    private func restartAnimationTimer() {
        animationTimer?.invalidate()
        jumpOffset = 0
        let interval = currentStage.animationIntervalSec
        guard interval > 0 else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.toggleJump() }
        }
    }

    private func toggleJump() {
        jumpOffset = jumpOffset == 0 ? -2 : 0
        renderIcon()
        // PNG 모드일 때는 image도 같은 effect 받게 텍스트 재그림 트리거
        renderText(percent: lastPercent, timeLeftSec: lastTimeLeftSec)
    }

    private func renderIcon() {
        guard let button = statusItem?.button, let set = currentSet else { return }
        let value = set.value(for: currentStage)

        switch set.type {
        case .emoji:
            // 이모지는 텍스트로. 펄쩍 효과는 attributed string baseline offset.
            // renderText가 attributedTitle을 다시 그리므로 여기서는 이미지만 비움.
            button.image = nil
        case .png:
            guard let folder = set.folderURL else { return }
            let path = folder.appendingPathComponent(value)
            if let image = NSImage(contentsOf: path) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = false
                button.image = image
                button.imagePosition = .imageLeading
            }
        }
    }

    private func renderText(percent: Int, timeLeftSec: Int) {
        guard let button = statusItem?.button, let set = currentSet else { return }

        var parts: [String] = []
        if showPercent { parts.append("\(percent)%") }
        if showTimeLeft { parts.append(formatTime(timeLeftSec)) }
        let suffix = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")

        let attrs: [NSAttributedString.Key: Any] = [.baselineOffset: jumpOffset]

        if set.type == .emoji {
            let baseValue = set.value(for: currentStage)
            let full = baseValue + suffix
            button.attributedTitle = NSAttributedString(string: full, attributes: attrs)
        } else {
            // PNG 모드 : 이미지는 따로, 텍스트만 attributedTitle
            button.attributedTitle = NSAttributedString(string: suffix, attributes: attrs)
            button.imagePosition = .imageLeading
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
