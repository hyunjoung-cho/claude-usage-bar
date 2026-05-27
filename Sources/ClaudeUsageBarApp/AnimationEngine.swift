import AppKit
import ClaudeUsageBarCore
import ImageIO

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

    // GIF 프레임 재생
    private var gifFrames: [NSImage] = []
    private var gifDurations: [TimeInterval] = []
    private var gifFrameIndex = 0
    private var gifTimer: Timer?
    private var playingKey: String?

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
            stopGIFPlayback()
            button.image = nil
        case .png:
            guard let folder = set.folderURL else { return }
            let path = folder.appendingPathComponent(value)

            // 같은 (set, stage) GIF가 이미 재생 중이면 skip
            let key = "\(set.name):\(currentStage.rawValue)"
            if gifTimer != nil && playingKey == key {
                return
            }

            // GIF 프레임 재생 시도
            let (frames, durations) = loadGIFFrames(from: path)
            if frames.count > 1 {
                playingKey = key
                startGIFPlayback(frames: frames, durations: durations)
            } else {
                // 단일 프레임 또는 비-GIF → 정적
                stopGIFPlayback()
                if let image = NSImage(contentsOf: path) {
                    image.size = NSSize(width: 18, height: 18)
                    image.isTemplate = false
                    button.image = image
                    button.imagePosition = .imageLeading
                }
            }
        }
    }

    // MARK: - GIF 헬퍼

    /// GIF 파일에서 프레임 NSImage 배열 + 각 프레임 표시 시간을 추출.
    /// GIF가 아니거나 단일 프레임이면 빈 배열 반환 (호출자가 정적 fallback).
    private func loadGIFFrames(from url: URL) -> (frames: [NSImage], durations: [TimeInterval]) {
        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ([], [])
        }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return ([], []) }   // 단일 프레임 = GIF 애니메이션 아님

        var frames: [NSImage] = []
        var durations: [TimeInterval] = []
        let targetSize = NSSize(width: 18, height: 18)

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let img = NSImage(cgImage: cg, size: targetSize)
            frames.append(img)

            // 프레임 delay 추출 (kCGImagePropertyGIFDelayTime)
            var delay: TimeInterval = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
               let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                    delay = unclamped
                } else if let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
                    delay = clamped
                }
            }
            // 너무 빠른 delay는 최소 0.05초로 클램프 (CPU 보호)
            durations.append(max(0.05, delay))
        }
        return (frames, durations)
    }

    private func startGIFPlayback(frames: [NSImage], durations: [TimeInterval]) {
        stopGIFPlayback()
        gifFrames = frames
        gifDurations = durations
        gifFrameIndex = 0
        showCurrentGIFFrame()
        scheduleNextGIFFrame()
    }

    private func stopGIFPlayback() {
        gifTimer?.invalidate()
        gifTimer = nil
        gifFrames = []
        gifDurations = []
        gifFrameIndex = 0
        playingKey = nil
    }

    private func showCurrentGIFFrame() {
        guard let button = statusItem?.button, gifFrameIndex < gifFrames.count else { return }
        let img = gifFrames[gifFrameIndex]
        img.isTemplate = false
        button.image = img
        button.imagePosition = .imageLeading
    }

    private func scheduleNextGIFFrame() {
        guard !gifFrames.isEmpty else { return }
        let duration = gifFrameIndex < gifDurations.count ? gifDurations[gifFrameIndex] : 0.1
        gifTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.gifFrameIndex = (self.gifFrameIndex + 1) % self.gifFrames.count
                self.showCurrentGIFFrame()
                self.scheduleNextGIFFrame()
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
