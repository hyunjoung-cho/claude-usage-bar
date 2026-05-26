import Foundation

/// `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl` 파일들을 스캔하여
/// 5h / 주간 / Opus 윈도우 사용량을 계산합니다.
public final class UsageScanner {
    private let projectsRoot: URL
    private let now: () -> Date

    public init(
        projectsRoot: URL = UsageScanner.defaultProjectsRoot,
        now: @escaping () -> Date = { Date() }
    ) {
        self.projectsRoot = projectsRoot
        self.now = now
    }

    public static let defaultProjectsRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude").appendingPathComponent("projects")
    }()

    /// 5h 윈도우 = 슬라이딩 (지금 시각 - 5h ~ 지금)
    /// 주간 윈도우 = 슬라이딩 (지금 - 7일 ~ 지금)
    /// Opus 윈도우 = 5h 윈도우 안에서 model 이름에 "opus" 포함된 메시지만 집계
    public func scan(limits: TokenLimits) -> Result<UsageData, PollError> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsRoot.path) else {
            return .failure(.noClaudeData)
        }

        let now = self.now()
        let fiveHourStart = now.addingTimeInterval(-5 * 3600)
        let weeklyStart   = now.addingTimeInterval(-7 * 24 * 3600)

        var fiveHourTotal = 0
        var weeklyTotal   = 0
        var opusTotal     = 0

        let urls: [URL]
        do {
            urls = try collectJsonlURLs()
        } catch {
            return .failure(.ioError(error.localizedDescription))
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let str = String(data: data, encoding: .utf8) else { continue }

            for line in str.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = line.data(using: .utf8),
                      let entry = try? JSONDecoder().decode(JsonlLine.self, from: lineData),
                      entry.type == "assistant",
                      let msg = entry.message,
                      let usage = msg.usage,
                      let tsStr = entry.timestamp,
                      let ts = formatter.date(from: tsStr) ?? formatterNoFrac.date(from: tsStr)
                else { continue }

                if ts < weeklyStart { continue }

                let tokens = usage.input_tokens
                           + (usage.cache_creation_input_tokens ?? 0)
                           + (usage.cache_read_input_tokens ?? 0)
                           + usage.output_tokens

                weeklyTotal += tokens

                if ts >= fiveHourStart {
                    fiveHourTotal += tokens
                    if (msg.model ?? "").lowercased().contains("opus") {
                        opusTotal += tokens
                    }
                }
            }
        }

        let fiveHourReset = now.addingTimeInterval(5 * 3600)
        let weeklyReset   = now.addingTimeInterval(7 * 24 * 3600)

        let usage = UsageData(
            fiveHourWindow: UsageWindow(usedTokens: fiveHourTotal, limitTokens: limits.fiveHour, resetsAt: fiveHourReset),
            weeklyWindow:   UsageWindow(usedTokens: weeklyTotal,   limitTokens: limits.weekly,   resetsAt: weeklyReset),
            opusWindow:     UsageWindow(usedTokens: opusTotal,     limitTokens: limits.opus,     resetsAt: fiveHourReset)
        )
        return .success(usage)
    }

    private func collectJsonlURLs() throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: projectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl" {
                urls.append(url)
            }
        }
        return urls
    }
}

// MARK: - JSONL line decoder

private struct JsonlLine: Decodable {
    let type: String?
    let timestamp: String?
    let message: AssistantMessage?

    struct AssistantMessage: Decodable {
        let model: String?
        let usage: Usage?

        struct Usage: Decodable {
            let input_tokens: Int
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
            let output_tokens: Int
        }
    }
}
