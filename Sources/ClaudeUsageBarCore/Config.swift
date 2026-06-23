import Foundation

public struct Config: Codable, Equatable {
    public let version: Int
    public var activeSet: String
    public var pollIntervalSec: Int
    public var thresholds: Thresholds
    public var showPercentInMenubar: Bool
    public var showTimeLeftInMenubar: Bool
    public var plan: ClaudePlan                 // NEW
    public var customLimits: TokenLimits?       // NEW — nil이면 plan.defaultLimits 사용
    /// GIF 재생 속도 배율. nil/기본 2.0 = 원본보다 2배 느리게(차분).
    /// 1.0 = 디자이너 원본 속도, 클수록 느림. 우클릭 메뉴에서 변경.
    public var animationSpeed: Double?          // NEW
    /// 캐릭터 움직임 on/off. nil/기본 true = 움직임.
    /// false = 첫 프레임 정지(버벅임/끊김 완전 제거). 우클릭 메뉴 "✨ 부드럽게"에서 변경.
    public var animationEnabled: Bool?          // NEW

    public init(
        version: Int,
        activeSet: String,
        pollIntervalSec: Int,
        thresholds: Thresholds,
        showPercentInMenubar: Bool,
        showTimeLeftInMenubar: Bool,
        plan: ClaudePlan = .pro,
        customLimits: TokenLimits? = nil,
        animationSpeed: Double? = nil,
        animationEnabled: Bool? = nil
    ) {
        self.version = version
        self.activeSet = activeSet
        self.pollIntervalSec = pollIntervalSec
        self.thresholds = thresholds
        self.showPercentInMenubar = showPercentInMenubar
        self.showTimeLeftInMenubar = showTimeLeftInMenubar
        self.plan = plan
        self.customLimits = customLimits
        self.animationSpeed = animationSpeed
        self.animationEnabled = animationEnabled
    }

    /// 실제 적용할 GIF 속도 배율 (nil이면 2.0배 = 차분).
    public var effectiveAnimationSpeed: Double {
        return animationSpeed ?? 2.0
    }

    /// 실제 적용할 캐릭터 움직임 여부 (nil이면 true = 움직임).
    public var effectiveAnimationEnabled: Bool {
        return animationEnabled ?? true
    }

    public static let `default` = Config(
        version: 1,
        activeSet: "emoji-faces",
        pollIntervalSec: 60,
        thresholds: .default,
        showPercentInMenubar: true,
        showTimeLeftInMenubar: true,
        plan: .pro,
        customLimits: nil
    )

    /// 실제 적용될 한도 (customLimits 있으면 그것, 없으면 plan.defaultLimits).
    public var effectiveLimits: TokenLimits {
        return customLimits ?? plan.defaultLimits
    }
}
