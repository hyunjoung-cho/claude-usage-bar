import Foundation

/// Plan별 토큰 한도 추정값. 사용자가 Settings에서 조정 가능.
public struct TokenLimits: Codable, Equatable {
    public var fiveHour: Int       // 5시간 윈도우 총 토큰 한도
    public var weekly: Int          // 7일 누적 토큰 한도
    public var opus: Int            // 5시간 윈도우 내 Opus 전용 한도

    public init(fiveHour: Int, weekly: Int, opus: Int) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.opus = opus
    }

    // 추정값 — Anthropic 공식 한도가 비공개라 커뮤니티 추정 기반.
    // 사용자가 본인 plan에 맞게 Settings에서 미세조정 가능.
    public static let pro    = TokenLimits(fiveHour:   50_000, weekly:  1_500_000, opus:   8_000)
    public static let max5x  = TokenLimits(fiveHour:  250_000, weekly:  7_500_000, opus:  40_000)
    public static let max20x = TokenLimits(fiveHour: 1_000_000, weekly: 30_000_000, opus: 160_000)
}

/// 사용자 Claude plan.
public enum ClaudePlan: String, Codable, CaseIterable, Equatable {
    case pro, max5x, max20x

    public var defaultLimits: TokenLimits {
        switch self {
        case .pro:    return .pro
        case .max5x:  return .max5x
        case .max20x: return .max20x
        }
    }

    public var displayName: String {
        switch self {
        case .pro:    return "Pro"
        case .max5x:  return "Max 5x"
        case .max20x: return "Max 20x"
        }
    }
}

/// 한 윈도우의 사용량.
public struct UsageWindow: Codable, Equatable {
    public let usedTokens: Int
    public let limitTokens: Int
    public let resetsAt: Date      // 윈도우가 reset되는 절대 시각

    public init(usedTokens: Int, limitTokens: Int, resetsAt: Date) {
        self.usedTokens = usedTokens
        self.limitTokens = limitTokens
        self.resetsAt = resetsAt
    }

    public var usedPercent: Int {
        guard limitTokens > 0 else { return 0 }
        let pct = (Double(usedTokens) / Double(limitTokens)) * 100.0
        return max(0, min(100, Int(pct.rounded())))
    }
}

/// 메뉴바에 표시할 사용량 데이터 (3개 윈도우).
public struct UsageData: Codable, Equatable {
    public let fiveHourWindow: UsageWindow
    public let weeklyWindow:   UsageWindow
    public let opusWindow:     UsageWindow

    public init(fiveHourWindow: UsageWindow, weeklyWindow: UsageWindow, opusWindow: UsageWindow) {
        self.fiveHourWindow = fiveHourWindow
        self.weeklyWindow   = weeklyWindow
        self.opusWindow     = opusWindow
    }
}

/// 스캔 실패 케이스.
public enum PollError: Error, Equatable {
    /// ~/.claude/projects 디렉토리가 없거나 비어있음
    case noClaudeData
    /// JSONL 파싱 실패 (raw error message 첨부)
    case parseError(String)
    /// 디스크 IO 실패 (raw error message 첨부)
    case ioError(String)
}
