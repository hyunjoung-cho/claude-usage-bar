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

// MARK: - 결과
print("\n━━━━━━━━━━━━━━━━━━━━━━━")
print("Total : \(passed + failed)")
print("✅ Pass : \(passed)")
print("❌ Fail : \(failed)")
print("━━━━━━━━━━━━━━━━━━━━━━━")
exit(failed > 0 ? 1 : 0)
