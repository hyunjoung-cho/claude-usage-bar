import Foundation

public struct UsageData: Codable, Equatable {
    public struct Window: Codable, Equatable {
        public let usedPercent: Int
        public let resetsAt: Date

        public init(usedPercent: Int, resetsAt: Date) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetsAt    = "resets_at"
        }
    }

    public let fiveHourWindow: Window
    public let weeklyWindow:   Window
    public let opusWindow:     Window

    public init(fiveHourWindow: Window, weeklyWindow: Window, opusWindow: Window) {
        self.fiveHourWindow = fiveHourWindow
        self.weeklyWindow = weeklyWindow
        self.opusWindow = opusWindow
    }

    enum CodingKeys: String, CodingKey {
        case fiveHourWindow = "five_hour_window"
        case weeklyWindow   = "weekly_window"
        case opusWindow     = "opus_window"
    }
}

public enum PollError: Error, Equatable {
    case noSessionKey
    case sessionExpired
    case schemaChanged(String)
    case network(String)

    public static func == (lhs: PollError, rhs: PollError) -> Bool {
        switch (lhs, rhs) {
        case (.noSessionKey, .noSessionKey):                          return true
        case (.sessionExpired, .sessionExpired):                      return true
        case (.schemaChanged(let a), .schemaChanged(let b)):          return a == b
        case (.network(let a), .network(let b)):                      return a == b
        default:                                                       return false
        }
    }
}
