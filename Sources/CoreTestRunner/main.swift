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

// MARK: - IconSet tests
suite("IconSet 파싱") {
    // 1. emoji 세트 파싱
    let emojiJSON = """
    {"name":"emoji-faces","type":"emoji","frames":{"chill":"😎","normal":"🙂","busy":"😰","danger":"🥵","burn":"🔥"}}
    """.data(using: .utf8)!
    do {
        let set = try JSONDecoder().decode(ClaudeUsageBarCore.IconSet.self, from: emojiJSON)
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
        let set = try JSONDecoder().decode(ClaudeUsageBarCore.IconSet.self, from: pngJSON)
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
        let set = try JSONDecoder().decode(ClaudeUsageBarCore.IconSet.self, from: partialJSON)
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
    check(Config.default.plan == .pro,                    "default plan = .pro")
    check(Config.default.customLimits == nil,             "default customLimits = nil")
    check(Config.default.effectiveLimits == TokenLimits.pro, "default effectiveLimits = pro limits")
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

// MARK: - IconSetLoader tests

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

suite("IconSetLoader — 모든 valid 세트 로드") {
    let root = uniqueTempDir("all-valid")
    writeSet(in: root, name: "emoji-faces", json: #"{"name":"emoji-faces","type":"emoji","frames":{"chill":"😎","normal":"🙂","busy":"😰","danger":"🥵","burn":"🔥"}}"#)
    writeSet(in: root, name: "emoji-stars", json: #"{"name":"emoji-stars","type":"emoji","frames":{"chill":"✨","normal":"🌟","busy":"💫","danger":"☄️","burn":"🔥"}}"#)
    let sets = IconSetLoader(rootURL: root).loadAll()
    check(sets.count == 2, "두 valid 세트 로드됨")
    check(sets.contains(where: { $0.name == "emoji-faces" }), "emoji-faces 포함")
    check(sets.contains(where: { $0.name == "emoji-stars" }), "emoji-stars 포함")
    try? FileManager.default.removeItem(at: root)
}

suite("IconSetLoader — 깨진 JSON 스킵") {
    let root = uniqueTempDir("skip-invalid")
    writeSet(in: root, name: "valid", json: #"{"name":"valid","type":"emoji","frames":{"chill":"😎","normal":"🙂","busy":"😰","danger":"🥵","burn":"🔥"}}"#)
    writeSet(in: root, name: "invalid", json: "{ not valid json")
    let sets = IconSetLoader(rootURL: root).loadAll()
    check(sets.count == 1, "깨진 json 스킵 → 1개만 로드")
    check(sets[0].name == "valid", "valid 세트만 살아남음")
    try? FileManager.default.removeItem(at: root)
}

suite("IconSetLoader — PNG 세트 folderURL 채워짐") {
    let root = uniqueTempDir("png-folder")
    writeSet(in: root, name: "my-claude-stars", json: #"{"name":"my-claude-stars","type":"png","frames":{"chill":"chill.png","normal":"normal.png","busy":"busy.png","danger":"danger.png","burn":"burn.png"}}"#)
    let sets = IconSetLoader(rootURL: root).loadAll()
    check(sets.count == 1, "png 세트 1개 로드")
    check(sets[0].folderURL != nil, "png 세트의 folderURL 채워짐")
    check(sets[0].folderURL!.lastPathComponent == "my-claude-stars", "folderURL이 해당 폴더를 가리킴")
    try? FileManager.default.removeItem(at: root)
}

suite("IconSetLoader — 빈 루트 → 빈 배열") {
    let root = uniqueTempDir("empty-root")
    check(IconSetLoader(rootURL: root).loadAll().count == 0, "빈 폴더 → 빈 배열")
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

// MARK: - UsageScanner 헬퍼

func uniqueClaudeRoot(_ tag: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-scan-\(tag)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url.appendingPathComponent("dummy-project"), withIntermediateDirectories: true)
    return url
}

func writeJsonlLine(in root: URL, project: String, sessionId: String, line: String) {
    let projectDir = root.appendingPathComponent(project)
    try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    let file = projectDir.appendingPathComponent("\(sessionId).jsonl")
    let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    try? (existing + line + "\n").write(to: file, atomically: true, encoding: .utf8)
}

func assistantJsonl(timestamp: String, model: String, input: Int, cacheCreate: Int, cacheRead: Int, output: Int) -> String {
    return #"{"type":"assistant","timestamp":"\#(timestamp)","message":{"model":"\#(model)","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreate),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output)}}}"#
}

// MARK: - UsageScanner tests

suite("UsageScanner — noClaudeData (존재하지 않는 디렉토리)") {
    let nonExistentURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-nonexistent-\(UUID().uuidString)")
    let scanner = UsageScanner(projectsRoot: nonExistentURL)
    let result = scanner.scan(limits: .pro)
    if case .failure(let err) = result, err == .noClaudeData {
        check(true, "존재하지 않는 디렉토리 → noClaudeData")
    } else {
        check(false, "기대 .noClaudeData, 실제 \(result)")
    }
}

suite("UsageScanner — 빈 디렉토리는 0 토큰") {
    let root = uniqueClaudeRoot("empty")
    let scanner = UsageScanner(projectsRoot: root)
    let result = scanner.scan(limits: .pro)
    if case .success(let usage) = result {
        check(usage.fiveHourWindow.usedTokens == 0, "fiveHourWindow usedTokens == 0")
        check(usage.weeklyWindow.usedTokens == 0,   "weeklyWindow usedTokens == 0")
        check(usage.opusWindow.usedTokens == 0,     "opusWindow usedTokens == 0")
    } else {
        check(false, "기대 .success, 실제 \(result)")
    }
    try? FileManager.default.removeItem(at: root)
}

suite("UsageScanner — 단일 assistant 라인 파싱") {
    let root = uniqueClaudeRoot("single-line")
    // fixedNow = 2026-05-26T12:00:00Z, timestamp = 1시간 전 = 2026-05-26T11:00:00Z
    let fixedNowStr = "2026-05-26T12:00:00Z"
    let oneHourAgoStr = "2026-05-26T11:00:00.000Z"   // fractional seconds 포함
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let fixedNow = formatter.date(from: fixedNowStr)!

    writeJsonlLine(in: root, project: "proj1", sessionId: "sess1",
        line: assistantJsonl(timestamp: oneHourAgoStr, model: "claude-sonnet-4-6",
                             input: 100, cacheCreate: 200, cacheRead: 300, output: 400))

    let scanner = UsageScanner(projectsRoot: root, now: { fixedNow })
    let result = scanner.scan(limits: .pro)
    if case .success(let usage) = result {
        // weighted: 100 + (200×1.25=250) + (300×0.1=30) + (400×5=2000) = 2380
        check(usage.fiveHourWindow.usedTokens == 2380, "fiveHourTotal == 2380 (weighted)")
        check(usage.opusWindow.usedTokens == 0,        "opusTotal == 0 (sonnet이라 Opus 아님)")
        check(usage.weeklyWindow.usedTokens == 2380,   "weeklyTotal == 2380 (weighted)")
        check(usage.fiveHourWindow.usedPercent == 0,   "fiveHour usedPercent == 0% (2380/6_000_000)")
    } else {
        check(false, "기대 .success, 실제 \(result)")
    }
    try? FileManager.default.removeItem(at: root)
}

suite("UsageScanner — Opus 모델만 opusTotal에 합산") {
    let root = uniqueClaudeRoot("opus-filter")
    let fixedNowStr = "2026-05-26T12:00:00Z"
    let thirtyMinAgoStr = "2026-05-26T11:30:00Z"   // fractional seconds 없는 형식
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let fixedNow = formatter.date(from: fixedNowStr)!

    // sonnet 500 토큰 (input 100 + cacheCreate 100 + cacheRead 100 + output 200 = 500)
    writeJsonlLine(in: root, project: "proj1", sessionId: "sess1",
        line: assistantJsonl(timestamp: thirtyMinAgoStr, model: "claude-sonnet-4-6",
                             input: 100, cacheCreate: 100, cacheRead: 100, output: 200))
    // opus 700 토큰 (input 200 + cacheCreate 200 + cacheRead 100 + output 200 = 700)
    writeJsonlLine(in: root, project: "proj1", sessionId: "sess1",
        line: assistantJsonl(timestamp: thirtyMinAgoStr, model: "claude-opus-4-7",
                             input: 200, cacheCreate: 200, cacheRead: 100, output: 200))

    let scanner = UsageScanner(projectsRoot: root, now: { fixedNow })
    let result = scanner.scan(limits: .pro)
    if case .success(let usage) = result {
        // Sonnet weighted: 100 + (100×1.25=125) + (100×0.1=10) + (200×5=1000) = 1235
        // Opus   weighted: 200 + (200×1.25=250) + (100×0.1=10) + (200×5=1000) = 1460
        check(usage.fiveHourWindow.usedTokens == 2695, "fiveHourTotal == 2695 (1235+1460, weighted)")
        check(usage.opusWindow.usedTokens == 1460,     "opusTotal == 1460 (opus 가중치 적용)")
        check(usage.weeklyWindow.usedTokens == 2695,   "weeklyTotal == 2695 (weighted)")
    } else {
        check(false, "기대 .success, 실제 \(result)")
    }
    try? FileManager.default.removeItem(at: root)
}

suite("UsageScanner — 5h 윈도우 밖 메시지는 제외") {
    let root = uniqueClaudeRoot("window-filter")
    let fixedNowStr = "2026-05-26T12:00:00Z"
    let sixHoursAgoStr = "2026-05-26T06:00:00Z"   // 6시간 전 — 5h 윈도우 밖
    let oneHourAgoStr = "2026-05-26T11:00:00Z"    // 1시간 전 — 5h 윈도우 안
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let fixedNow = formatter.date(from: fixedNowStr)!

    // 6시간 전 메시지 1000 토큰
    writeJsonlLine(in: root, project: "proj1", sessionId: "sess1",
        line: assistantJsonl(timestamp: sixHoursAgoStr, model: "claude-sonnet-4-6",
                             input: 250, cacheCreate: 250, cacheRead: 250, output: 250))
    // 1시간 전 메시지 1000 토큰
    writeJsonlLine(in: root, project: "proj1", sessionId: "sess1",
        line: assistantJsonl(timestamp: oneHourAgoStr, model: "claude-sonnet-4-6",
                             input: 250, cacheCreate: 250, cacheRead: 250, output: 250))

    let scanner = UsageScanner(projectsRoot: root, now: { fixedNow })
    let result = scanner.scan(limits: .pro)
    if case .success(let usage) = result {
        // weighted per line: 250 + (250×1.25=312) + (250×0.1=25) + (250×5=1250) = 1837
        check(usage.fiveHourWindow.usedTokens == 1837, "fiveHourTotal == 1837 (1시간 전만, weighted)")
        check(usage.weeklyWindow.usedTokens == 3674,   "weeklyTotal == 3674 (둘 다 주간 안, weighted)")
    } else {
        check(false, "기대 .success, 실제 \(result)")
    }
    try? FileManager.default.removeItem(at: root)
}

// MARK: - 결과
print("\n━━━━━━━━━━━━━━━━━━━━━━━")
print("Total : \(passed + failed)")
print("✅ Pass : \(passed)")
print("❌ Fail : \(failed)")
print("━━━━━━━━━━━━━━━━━━━━━━━")
exit(failed > 0 ? 1 : 0)
