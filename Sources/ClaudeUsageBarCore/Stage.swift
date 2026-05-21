import Foundation

enum Stage: String, Codable, CaseIterable, Equatable {
    case chill, normal, busy, danger, burn

    static func from(percent: Int, thresholds: Thresholds) -> Stage {
        if percent < thresholds.chillMax  { return .chill }
        if percent < thresholds.normalMax { return .normal }
        if percent < thresholds.busyMax   { return .busy }
        if percent < thresholds.dangerMax { return .danger }
        return .burn
    }

    var animationIntervalSec: TimeInterval {
        switch self {
        case .chill, .normal: return 0
        case .busy:           return 2.0
        case .danger:         return 1.0
        case .burn:           return 0.5
        }
    }
}

struct Thresholds: Codable, Equatable {
    var chillMax:  Int
    var normalMax: Int
    var busyMax:   Int
    var dangerMax: Int

    static let `default` = Thresholds(chillMax: 40, normalMax: 70, busyMax: 85, dangerMax: 95)
}
