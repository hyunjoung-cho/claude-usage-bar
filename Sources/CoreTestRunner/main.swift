import Foundation
import ClaudeUsageBarCore

// MARK: - 테스트 헬퍼 (커스텀 assertion runner)
var passed = 0
var failed = 0

func check(_ condition: Bool, _ label: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
        print("  ✅ \(label)")
    } else {
        failed += 1
        let filename = (file as NSString).lastPathComponent
        print("  ❌ \(label)  (\(filename):\(line))")
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n▶︎ \(name)")
    body()
}

// MARK: - Stage tests
suite("Stage 단계 계산") {
    let t = Thresholds(chillMax: 40, normalMax: 70, busyMax: 85, dangerMax: 95)
    check(Stage.from(percent: 0,   thresholds: t) == .chill,  "0%   → chill")
    check(Stage.from(percent: 39,  thresholds: t) == .chill,  "39%  → chill")
    check(Stage.from(percent: 40,  thresholds: t) == .normal, "40%  → normal")
    check(Stage.from(percent: 69,  thresholds: t) == .normal, "69%  → normal")
    check(Stage.from(percent: 70,  thresholds: t) == .busy,   "70%  → busy")
    check(Stage.from(percent: 84,  thresholds: t) == .busy,   "84%  → busy")
    check(Stage.from(percent: 85,  thresholds: t) == .danger, "85%  → danger")
    check(Stage.from(percent: 94,  thresholds: t) == .danger, "94%  → danger")
    check(Stage.from(percent: 95,  thresholds: t) == .burn,   "95%  → burn")
    check(Stage.from(percent: 100, thresholds: t) == .burn,   "100% → burn")
    check(Stage.from(percent: 999, thresholds: t) == .burn,   "999% → burn")
}

suite("Stage 애니메이션 간격") {
    check(Stage.chill.animationIntervalSec  == 0,   "chill  = 0s")
    check(Stage.normal.animationIntervalSec == 0,   "normal = 0s")
    check(Stage.busy.animationIntervalSec   == 2.0, "busy   = 2s")
    check(Stage.danger.animationIntervalSec == 1.0, "danger = 1s")
    check(Stage.burn.animationIntervalSec   == 0.5, "burn   = 0.5s")
}

// MARK: - CharacterSet tests
suite("CharacterSet 파싱") {
    // 1. emoji 세트 파싱
    let emojiJSON = """
    {"name":"emoji-faces","type":"emoji","frames":{"chill":"😎","normal":"🙂","busy":"😰","danger":"🥵","burn":"🔥"}}
    """.data(using: .utf8)!
    do {
        let set = try JSONDecoder().decode(ClaudeUsageBarCore.CharacterSet.self, from: emojiJSON)
        check(set.name == "emoji-faces",         "emoji 세트 name 파싱")
        check(set.type == .emoji,                "emoji 세트 type 파싱")
        check(set.value(for: .chill) == "😎",    "emoji chill 프레임")
        check(set.value(for: .burn)  == "🔥",    "emoji burn 프레임")
    } catch {
        check(false, "emoji 세트 디코딩 실패: \(error)")
    }

    // 2. png 세트 파싱
    let pngJSON = """
    {"name":"my-claude-stars","type":"png","frames":{"chill":"chill.png","normal":"normal.png","busy":"busy.png","danger":"danger.png","burn":"burn.png"}}
    """.data(using: .utf8)!
    do {
        let set = try JSONDecoder().decode(ClaudeUsageBarCore.CharacterSet.self, from: pngJSON)
        check(set.type == .png,                        "png 세트 type 파싱")
        check(set.value(for: .danger) == "danger.png", "png danger 프레임")
    } catch {
        check(false, "png 세트 디코딩 실패: \(error)")
    }

    // 3. missing frame fallback
    let partialJSON = """
    {"name":"partial","type":"emoji","frames":{"chill":"😎"}}
    """.data(using: .utf8)!
    do {
        let set = try JSONDecoder().decode(ClaudeUsageBarCore.CharacterSet.self, from: partialJSON)
        check(set.value(for: .chill) == "😎", "partial chill 프레임 존재")
        check(set.value(for: .burn)  == "?",  "partial burn 프레임 누락 → ?")
    } catch {
        check(false, "partial 세트 디코딩 실패: \(error)")
    }
}

// MARK: - Config + ConfigStore tests

func uniqueTempURL(_ tag: String) -> URL {
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("config-test-\(tag)-\(UUID().uuidString).json")
}

suite("Config 기본값 검증") {
    check(Config.default.version == 1,                    "default version = 1")
    check(Config.default.activeSet == "emoji-faces",      "default activeSet = emoji-faces")
    check(Config.default.pollIntervalSec == 60,           "default pollIntervalSec = 60")
    check(Config.default.showPercentInMenubar == true,    "default showPercentInMenubar = true")
    check(Config.default.showTimeLeftInMenubar == true,   "default showTimeLeftInMenubar = true")
    check(Config.default.thresholds.chillMax == 40,       "default chillMax = 40")
    check(Config.default.thresholds.normalMax == 70,      "default normalMax = 70")
    check(Config.default.thresholds.busyMax == 85,        "default busyMax = 85")
    check(Config.default.thresholds.dangerMax == 95,      "default dangerMax = 95")
}

suite("ConfigStore 파일 없을 때 default 생성") {
    let url = uniqueTempURL("missing")
    do {
        let store = ConfigStore(url: url)
        let config = try store.load()
        check(config == .default, "missing file → returns default")
        check(FileManager.default.fileExists(atPath: url.path), "missing file → side-effect: file created")
    } catch {
        check(false, "missing file 로드 실패: \(error)")
    }
    try? FileManager.default.removeItem(at: url)
}

suite("ConfigStore 저장 후 로드 (round-trip)") {
    let url = uniqueTempURL("roundtrip")
    do {
        let store = ConfigStore(url: url)
        var config = Config.default
        config.activeSet = "emoji-stars"
        config.pollIntervalSec = 30
        try store.save(config)
        let loaded = try store.load()
        check(loaded.activeSet == "emoji-stars",  "round-trip: activeSet preserved")
        check(loaded.pollIntervalSec == 30,        "round-trip: pollIntervalSec preserved")
    } catch {
        check(false, "round-trip 실패: \(error)")
    }
    try? FileManager.default.removeItem(at: url)
}

// MARK: - CharacterSetLoader tests

func uniqueTempDir(_ tag: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sets-test-\(tag)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeSet(in root: URL, name: String, json: String) {
    let folder = root.appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let setJSON = folder.appendingPathComponent("set.json")
    try? json.write(to: setJSON, atomically: true, encoding: .utf8)
}

suite("CharacterSetLoader — 모든 valid 세트 로드") {
    let root = uniqueTempDir("all-valid")
    writeSet(in: root, name: "emoji-faces", json: #"{"name":"emoji-faces","type":"emoji","frames":{"chill":"😎","normal":"🙂","busy":"😰","danger":"🥵","burn":"🔥"}}"#)
    writeSet(in: root, name: "emoji-stars", json: #"{"name":"emoji-stars","type":"emoji","frames":{"chill":"✨","normal":"🌟","busy":"💫","danger":"☄️","burn":"🔥"}}"#)
    let sets = CharacterSetLoader(rootURL: root).loadAll()
    check(sets.count == 2, "두 valid 세트 로드됨")
    check(sets.contains(where: { $0.name == "emoji-faces" }), "emoji-faces 포함")
    check(sets.contains(where: { $0.name == "emoji-stars" }), "emoji-stars 포함")
    try? FileManager.default.removeItem(at: root)
}

suite("CharacterSetLoader — 깨진 JSON 스킵") {
    let root = uniqueTempDir("skip-invalid")
    writeSet(in: root, name: "valid", json: #"{"name":"valid","type":"emoji","frames":{"chill":"😎","normal":"🙂","busy":"😰","danger":"🥵","burn":"🔥"}}"#)
    writeSet(in: root, name: "invalid", json: "{ not valid json")
    let sets = CharacterSetLoader(rootURL: root).loadAll()
    check(sets.count == 1, "깨진 json 스킵 → 1개만 로드")
    check(sets[0].name == "valid", "valid 세트만 살아남음")
    try? FileManager.default.removeItem(at: root)
}

suite("CharacterSetLoader — PNG 세트 folderURL 채워짐") {
    let root = uniqueTempDir("png-folder")
    writeSet(in: root, name: "my-claude-stars", json: #"{"name":"my-claude-stars","type":"png","frames":{"chill":"chill.png","normal":"normal.png","busy":"busy.png","danger":"danger.png","burn":"burn.png"}}"#)
    let sets = CharacterSetLoader(rootURL: root).loadAll()
    check(sets.count == 1, "png 세트 1개 로드")
    check(sets[0].folderURL != nil, "png 세트의 folderURL 채워짐")
    check(sets[0].folderURL!.lastPathComponent == "my-claude-stars", "folderURL이 해당 폴더를 가리킴")
    try? FileManager.default.removeItem(at: root)
}

suite("CharacterSetLoader — 빈 루트 → 빈 배열") {
    let root = uniqueTempDir("empty-root")
    check(CharacterSetLoader(rootURL: root).loadAll().count == 0, "빈 폴더 → 빈 배열")
    try? FileManager.default.removeItem(at: root)
}

// MARK: - SessionKeyManager tests

/// 각 테스트마다 고유한 Keychain service ID를 생성합니다.
/// → 테스트 간 충돌 방지, 실제 프로덕션 데이터와도 완전 격리.
/// NOTE: macOS CLI 툴이 Keychain에 처음 접근할 때 "Always Allow / Deny" 팝업이
///       뜰 수 있습니다. "Always Allow"를 한 번 클릭한 뒤 `make test`를 재실행하세요.
func uniqueKeychainService(_ tag: String) -> String {
    return "com.goldplat.claude-usage-bar.test.\(tag).\(UUID().uuidString)"
}

suite("SessionKeyManager — 빈 keychain load nil") {
    let manager = SessionKeyManager(service: uniqueKeychainService("empty"))
    check(manager.load() == nil, "빈 keychain → load nil")
    manager.delete()  // cleanup
}

suite("SessionKeyManager — save 후 load 값 일치") {
    let manager = SessionKeyManager(service: uniqueKeychainService("save-load"))
    do {
        try manager.save("abc123-session-key")
        check(manager.load() == "abc123-session-key", "save 후 load 값 일치")
    } catch {
        check(false, "save 실패: \(error)")
    }
    manager.delete()
}

suite("SessionKeyManager — save 덮어쓰기") {
    let manager = SessionKeyManager(service: uniqueKeychainService("overwrite"))
    do {
        try manager.save("first")
        try manager.save("second")
        check(manager.load() == "second", "두 번째 save가 첫 값을 덮어씀")
    } catch {
        check(false, "save 덮어쓰기 실패: \(error)")
    }
    manager.delete()
}

suite("SessionKeyManager — delete 후 load nil") {
    let manager = SessionKeyManager(service: uniqueKeychainService("delete"))
    do {
        try manager.save("to-delete")
        manager.delete()
        check(manager.load() == nil, "delete 후 load nil")
    } catch {
        check(false, "save 실패: \(error)")
    }
}

// MARK: - Async helpers

func runAsync<T>(_ body: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?
    Task {
        result = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return result!
}

func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - UsagePoller tests

suite("UsagePoller fetchOnce — noSessionKey") {
    MockURLProtocol.reset()
    let keyManager = SessionKeyManager(service: uniqueKeychainService("no-key"))
    let poller = UsagePoller(keyManager: keyManager, session: mockSession())
    let result = runAsync { await poller.fetchOnce() }
    if case .failure(let err) = result, err == .noSessionKey {
        check(true, "키 없음 → noSessionKey")
    } else {
        check(false, "기대 .noSessionKey, 실제 \(result)")
    }
    keyManager.delete()
}

suite("UsagePoller fetchOnce — sessionExpired on HTTP 401") {
    MockURLProtocol.reset()
    let keyManager = SessionKeyManager(service: uniqueKeychainService("session-expired"))
    do {
        try keyManager.save("dummy")
        MockURLProtocol.responder = { _ in
            (HTTPURLResponse(url: URL(string: "https://claude.ai")!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        let poller = UsagePoller(keyManager: keyManager, session: mockSession())
        let result = runAsync { await poller.fetchOnce() }
        if case .failure(let err) = result, err == .sessionExpired {
            check(true, "HTTP 401 → sessionExpired")
        } else {
            check(false, "기대 .sessionExpired, 실제 \(result)")
        }
    } catch {
        check(false, "save 실패: \(error)")
    }
    keyManager.delete()
}

suite("UsagePoller fetchOnce — success parses usage") {
    MockURLProtocol.reset()
    let keyManager = SessionKeyManager(service: uniqueKeychainService("success-parse"))
    do {
        try keyManager.save("dummy")
        let json = """
        {
          "five_hour_window": {"used_percent":67,"resets_at":"2026-05-20T18:30:00Z"},
          "weekly_window":    {"used_percent":42,"resets_at":"2026-05-25T00:00:00Z"},
          "opus_window":      {"used_percent":12,"resets_at":"2026-05-20T18:30:00Z"}
        }
        """.data(using: .utf8)!
        MockURLProtocol.responder = { _ in
            (HTTPURLResponse(url: URL(string: "https://claude.ai")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let poller = UsagePoller(keyManager: keyManager, session: mockSession())
        let result = runAsync { await poller.fetchOnce() }
        if case .success(let usage) = result {
            check(usage.fiveHourWindow.usedPercent == 67, "fiveHourWindow.usedPercent == 67")
            check(usage.weeklyWindow.usedPercent   == 42, "weeklyWindow.usedPercent == 42")
            check(usage.opusWindow.usedPercent     == 12, "opusWindow.usedPercent == 12")
        } else {
            check(false, "기대 .success, 실제 \(result)")
        }
    } catch {
        check(false, "save 실패: \(error)")
    }
    keyManager.delete()
}

suite("UsagePoller fetchOnce — schemaChanged on bad JSON") {
    MockURLProtocol.reset()
    let keyManager = SessionKeyManager(service: uniqueKeychainService("schema-changed"))
    do {
        try keyManager.save("dummy")
        let badJSON = #"{"unexpected":"shape"}"#.data(using: .utf8)!
        MockURLProtocol.responder = { _ in
            (HTTPURLResponse(url: URL(string: "https://claude.ai")!, statusCode: 200, httpVersion: nil, headerFields: nil)!, badJSON)
        }
        let poller = UsagePoller(keyManager: keyManager, session: mockSession())
        let result = runAsync { await poller.fetchOnce() }
        if case .failure(let err) = result, case .schemaChanged(_) = err {
            check(true, "잘못된 JSON → schemaChanged")
        } else {
            check(false, "기대 .schemaChanged, 실제 \(result)")
        }
    } catch {
        check(false, "save 실패: \(error)")
    }
    keyManager.delete()
}

// MARK: - 결과
print("\n━━━━━━━━━━━━━━━━━━━━━━━")
print("Total : \(passed + failed)")
print("✅ Pass : \(passed)")
print("❌ Fail : \(failed)")
print("━━━━━━━━━━━━━━━━━━━━━━━")
exit(failed > 0 ? 1 : 0)
