import Foundation

public final class ConfigStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static let defaultURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ClaudeUsageBar")
            .appendingPathComponent("config.json")
    }()

    /// 설정 파일을 로드합니다.
    /// 파일이 존재하지 않을 경우 기본값으로 새 파일을 생성한 뒤 반환합니다.
    public func load() throws -> Config {
        if !FileManager.default.fileExists(atPath: url.path) {
            try save(.default)
            return .default
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
