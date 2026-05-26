import Foundation

public final class IconSetLoader {
    private let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static let defaultRootURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("ClaudeUsageBar")
            .appendingPathComponent("sets")
    }()

    /// rootURL 아래 1단계 폴더들을 스캔하여 각 폴더의 `set.json`을 파싱한 결과를 반환합니다.
    /// JSON이 깨졌거나 파일이 없는 폴더는 건너뜁니다.
    /// PNG 타입 세트는 `folderURL`을 자동으로 채워줍니다.
    /// 결과는 이름 오름차순으로 정렬됩니다.
    public func loadAll() -> [IconSet] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var result: [IconSet] = []
        for folder in folders {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let setJSON = folder.appendingPathComponent("set.json")
            guard let data = try? Data(contentsOf: setJSON),
                  var set = try? JSONDecoder().decode(IconSet.self, from: data)
            else { continue }
            if set.type == .png { set.folderURL = folder }
            result.append(set)
        }
        return result.sorted { $0.name < $1.name }
    }

    public func set(named name: String) -> IconSet? {
        loadAll().first { $0.name == name }
    }
}
