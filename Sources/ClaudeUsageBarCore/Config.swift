import Foundation

public struct Config: Codable, Equatable {
    public let version: Int
    public var activeSet: String
    public var pollIntervalSec: Int
    public var thresholds: Thresholds
    public var showPercentInMenubar: Bool
    public var showTimeLeftInMenubar: Bool

    public init(
        version: Int,
        activeSet: String,
        pollIntervalSec: Int,
        thresholds: Thresholds,
        showPercentInMenubar: Bool,
        showTimeLeftInMenubar: Bool
    ) {
        self.version = version
        self.activeSet = activeSet
        self.pollIntervalSec = pollIntervalSec
        self.thresholds = thresholds
        self.showPercentInMenubar = showPercentInMenubar
        self.showTimeLeftInMenubar = showTimeLeftInMenubar
    }

    public static let `default` = Config(
        version: 1,
        activeSet: "emoji-faces",
        pollIntervalSec: 60,
        thresholds: .default,
        showPercentInMenubar: true,
        showTimeLeftInMenubar: true
    )
}
