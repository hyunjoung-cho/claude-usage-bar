import Foundation

public enum Stage: String, Codable, CaseIterable, Equatable {
    case chill, normal, busy, danger, burn

    public static func from(percent: Int, thresholds: Thresholds) -> Stage {
        if percent < thresholds.chillMax  { return .chill }
        if percent < thresholds.normalMax { return .normal }
        if percent < thresholds.busyMax   { return .busy }
        if percent < thresholds.dangerMax { return .danger }
        return .burn
    }

    public var animationIntervalSec: TimeInterval {
        switch self {
        case .chill, .normal: return 0
        case .busy:           return 2.0
        case .danger:         return 1.0
        case .burn:           return 0.5
        }
    }
}

public struct Thresholds: Codable, Equatable {
    public var chillMax:  Int
    public var normalMax: Int
    public var busyMax:   Int
    public var dangerMax: Int

    public init(chillMax: Int, normalMax: Int, busyMax: Int, dangerMax: Int) {
        self.chillMax = chillMax
        self.normalMax = normalMax
        self.busyMax = busyMax
        self.dangerMax = dangerMax
    }

    public static let `default` = Thresholds(chillMax: 40, normalMax: 70, busyMax: 85, dangerMax: 95)
}
