import AppKit
import ClaudeUsageBarCore
import ImageIO
import QuartzCore

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
    /// GIF 프레임 delay에 곱하는 배율. 1.0 = 원본속도, 클수록 느림. 기본 2.0(차분).
    private var speedMultiplier: Double = 2.0
    /// 캐릭터 움직임 on/off. false면 첫 프레임만 정지 표시(끊김 완전 제거).
    private var animationEnabled: Bool = true

    // GIF 프레임 재생 (시계 기반 — 메인스레드가 잠깐 막혀도 올바른 프레임으로 자가보정)
    private var gifFrames: [NSImage] = []
    private var gifDurations: [TimeInterval] = []
    private var gifCumulative: [TimeInterval] = []   // 각 프레임이 끝나는 누적 시각
    private var gifLoopDuration: TimeInterval = 0
    private var gifStartTime: CFTimeInterval = 0
    private var gifFrameIndex = -1
    private var gifTimer: Timer?
    private var playingKey: String?

    /// 디코딩 캐시: 경로 → (프레임, 원본 delay). 60초 update마다 디스크 재디코딩을 막아
    /// 스크래이프 순간의 메인스레드 멈칫("가끔 버벅")을 제거한다.
    private var frameCache: [String: (frames: [NSImage], delays: [TimeInterval])] = [:]

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

    /// GIF 재생 속도 배율을 바꾸고 현재 재생 중인 GIF에 즉시 반영한다.
    func use(speedMultiplier: Double) {
        let clamped = max(0.25, speedMultiplier)   // 0.25배(4배 빠름)~ 안전 하한
        guard clamped != self.speedMultiplier else { return }
        self.speedMultiplier = clamped
        // 재생 중 GIF를 강제로 다시 로드해 새 속도로 재생.
        playingKey = nil
        renderIcon()
    }

    /// 캐릭터 움직임 on/off. off면 첫 프레임 정지(끊김 완전 제거), on이면 다시 재생.
    func use(animationEnabled: Bool) {
        guard animationEnabled != self.animationEnabled else { return }
        self.animationEnabled = animationEnabled
        playingKey = nil
        renderIcon()
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
        // .common 모드로 등록 — 메뉴를 열거나 트래킹 중에도 멈추지 않는다.
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.toggleJump() }
        }
        RunLoop.main.add(t, forMode: .common)
        animationTimer = t
    }

    private func toggleJump() {
        // 펄쩍 효과는 이모지(텍스트) 캐릭터에만 적용한다.
        // GIF/PNG 세트는 GIF 자체가 프레임 애니메이션으로 펄쩍거리므로,
        // 텍스트 baseline까지 흔들면 퍼센트 글씨가 같이 요동쳐 가독성을 해친다.
        guard currentSet?.type == .emoji else { return }
        jumpOffset = jumpOffset == 0 ? -2 : 0
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

            let (frames, delays) = loadGIFFrames(from: path)

            // 움직임이 켜져 있고 멀티프레임 GIF일 때만 애니메이션. 그 외엔 첫 프레임 정지.
            let shouldAnimate = animationEnabled && frames.count > 1

            if shouldAnimate {
                // 같은 (set, stage, speed) GIF가 이미 재생 중이면 skip
                let key = "\(set.name):\(currentStage.rawValue):\(speedMultiplier)"
                if gifTimer != nil && playingKey == key { return }
                playingKey = key
                startGIFPlayback(frames: frames, delays: delays)
            } else {
                // 정지 프레임 : GIF면 첫 프레임, 아니면 파일 이미지
                stopGIFPlayback()
                if let image = frames.first ?? NSImage(contentsOf: path) {
                    image.size = NSSize(width: 18, height: 18)
                    image.isTemplate = false
                    button.image = image
                    button.imagePosition = .imageLeading
                }
            }
        }
    }

    // MARK: - GIF 헬퍼

    /// GIF 파일에서 프레임 NSImage 배열 + 각 프레임 원본 delay를 추출.
    /// 한 번 디코딩하면 캐시한다 (60초 update마다 재디코딩 방지 = 메인스레드 멈칫 제거).
    /// GIF가 아니거나 단일 프레임이면 빈 배열 반환 (호출자가 정적 fallback).
    private func loadGIFFrames(from url: URL) -> (frames: [NSImage], delays: [TimeInterval]) {
        let cacheKey = url.path
        if let cached = frameCache[cacheKey] { return cached }

        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ([], [])
        }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return ([], []) }   // 단일 프레임 = GIF 애니메이션 아님

        var frames: [NSImage] = []
        var delays: [TimeInterval] = []
        let targetSize = NSSize(width: 18, height: 18)

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(NSImage(cgImage: cg, size: targetSize))

            // 프레임 delay 추출 (kCGImagePropertyGIFDelayTime). 속도배율은 재생 시 적용.
            var delay: TimeInterval = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
               let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                    delay = unclamped
                } else if let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double, clamped > 0 {
                    delay = clamped
                }
            }
            delays.append(delay)
        }
        let result = (frames, delays)
        frameCache[cacheKey] = result
        return result
    }

    private func startGIFPlayback(frames: [NSImage], delays: [TimeInterval]) {
        gifTimer?.invalidate()
        gifTimer = nil
        gifFrames = frames
        // 원본 delay에 속도 배율을 곱한다(클수록 느림). 너무 빠른 delay만 0.05초로 클램프(CPU 보호).
        gifDurations = delays.map { max(0.05, $0 * speedMultiplier) }

        // 각 프레임이 끝나는 누적 시각 테이블 — 시계 기반 프레임 선택에 사용.
        var cum: [TimeInterval] = []
        var total: TimeInterval = 0
        for d in gifDurations { total += d; cum.append(total) }
        gifCumulative = cum
        gifLoopDuration = max(total, 0.05)
        gifStartTime = CACurrentMediaTime()
        gifFrameIndex = -1
        tickGIF()
    }

    private func stopGIFPlayback() {
        gifTimer?.invalidate()
        gifTimer = nil
        gifFrames = []
        gifDurations = []
        gifCumulative = []
        gifLoopDuration = 0
        gifFrameIndex = -1
        playingKey = nil
    }

    /// 경과 시간(단조 시계)으로 지금 보여야 할 프레임을 직접 계산한다.
    /// 메인스레드가 잠깐 막혀 타이머가 늦게 깨어나도, 밀린 프레임을 하나씩
    /// 따라잡지 않고 곧장 올바른 프레임으로 점프 → "정지했다 재생"하는 버벅임이 사라진다.
    private func tickGIF() {
        guard !gifFrames.isEmpty, gifLoopDuration > 0 else { return }

        let now = CACurrentMediaTime()
        let elapsed = (now - gifStartTime).truncatingRemainder(dividingBy: gifLoopDuration)

        // elapsed가 속한 프레임 index 찾기
        var idx = 0
        while idx < gifCumulative.count - 1 && elapsed >= gifCumulative[idx] { idx += 1 }

        if idx != gifFrameIndex {
            gifFrameIndex = idx
            showCurrentGIFFrame()
        }

        // 다음 프레임 경계까지 남은 시간만큼만 잔다. (.common 모드 = 메뉴 떠도 안 멈춤)
        let boundary = gifCumulative[idx]
        var delay = boundary - elapsed
        if delay < 0.01 { delay = 0.01 }

        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tickGIF() }
        }
        RunLoop.main.add(t, forMode: .common)
        gifTimer = t
    }

    private func showCurrentGIFFrame() {
        guard let button = statusItem?.button, gifFrameIndex >= 0, gifFrameIndex < gifFrames.count else { return }
        let img = gifFrames[gifFrameIndex]
        img.isTemplate = false
        button.image = img
        button.imagePosition = .imageLeading
    }

    private func renderText(percent: Int, timeLeftSec: Int) {
        guard let button = statusItem?.button, let set = currentSet else { return }

        var parts: [String] = []
        if showPercent { parts.append("\(percent)%") }
        if showTimeLeft { parts.append(formatTime(timeLeftSec)) }
        let suffix = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")

        if set.type == .emoji {
            let baseValue = set.value(for: currentStage)
            let full = baseValue + suffix
            let attr = NSMutableAttributedString(string: full)
            // 펄쩍 효과는 이모지 글자에만. 퍼센트/시간 텍스트는 고정해 가독성을 지킨다.
            let emojiLen = (baseValue as NSString).length
            if emojiLen > 0 {
                attr.addAttribute(.baselineOffset, value: jumpOffset,
                                  range: NSRange(location: 0, length: emojiLen))
            }
            button.attributedTitle = attr
        } else {
            // PNG/GIF 모드 : 이미지는 GIF가 스스로 애니메이션하므로 텍스트는 흔들지 않는다.
            button.attributedTitle = NSAttributedString(string: suffix)
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
