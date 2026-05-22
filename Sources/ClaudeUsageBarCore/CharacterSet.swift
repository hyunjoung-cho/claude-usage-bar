import Foundation

public enum SetType: String, Codable, Equatable {
    case emoji, png
}

public struct CharacterSet: Codable, Equatable {
    public let name: String
    public let type: SetType
    public let frames: [String: String]

    // PNG 타입일 때 Loader가 채워줌 (set.json이 있는 폴더 URL)
    public var folderURL: URL?

    public init(name: String, type: SetType, frames: [String: String], folderURL: URL? = nil) {
        self.name = name
        self.type = type
        self.frames = frames
        self.folderURL = folderURL
    }

    enum CodingKeys: String, CodingKey { case name, type, frames }

    public func value(for stage: Stage) -> String {
        return frames[stage.rawValue] ?? "?"
    }
}
