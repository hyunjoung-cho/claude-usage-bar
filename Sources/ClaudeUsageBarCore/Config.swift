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

    public init(
        version: Int,
        activeSet: String,
        pollIntervalSec: Int,
        thresholds: Thresholds,
        showPercentInMenubar: Bool,
        showTimeLeftInMenubar: Bool,
        plan: ClaudePlan = .pro,
        customLimits: TokenLimits? = nil
    ) {
        self.version = version
        self.activeSet = activeSet
        self.pollIntervalSec = pollIntervalSec
        self.thresholds = thresholds
        self.showPercentInMenubar = showPercentInMenubar
        self.showTimeLeftInMenubar = showTimeLeftInMenubar
        self.plan = plan
        self.customLimits = customLimits
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
