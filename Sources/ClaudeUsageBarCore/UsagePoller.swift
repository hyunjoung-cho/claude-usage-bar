import Foundation

public final class UsagePoller {
    private let scanner: UsageScanner
    public var limits: TokenLimits   // mutable, AppDelegate가 plan 바뀔 때 갱신

    /// 폴링 성공 시 호출됩니다.
    /// - Warning: 콜백은 임의 스레드에서 호출됩니다. AppKit/SwiftUI 업데이트는 반드시
    ///   `DispatchQueue.main.async` 또는 `@MainActor`로 감싸세요.
    public var onUpdate: ((UsageData) -> Void)?

    /// 폴링 실패 시 호출됩니다.
    /// - Warning: 콜백은 임의 스레드에서 호출됩니다. AppKit/SwiftUI 업데이트는 반드시
    ///   `DispatchQueue.main.async` 또는 `@MainActor`로 감싸세요.
    public var onError: ((PollError) -> Void)?

    private var timer: Timer?

    public init(scanner: UsageScanner = UsageScanner(), limits: TokenLimits = .pro) {
        self.scanner = scanner
        self.limits = limits
    }

    public func start(intervalSec: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSec), repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
        Task { await tick() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        let result = await fetchOnce()
        switch result {
        case .success(let usage): onUpdate?(usage)
        case .failure(let err):   onError?(err)
        }
    }

    /// 디스크에서 Claude Code 사용량을 한 번 스캔합니다.
    public func fetchOnce() async -> Result<UsageData, PollError> {
        return scanner.scan(limits: limits)
    }
}
