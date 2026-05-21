import Foundation
@testable import ClaudeUsageBarCore

let thresholds = Thresholds(chillMax: 40, normalMax: 70, busyMax: 85, dangerMax: 95)

var testCount = 0
var passCount = 0

func test(_ name: String, condition: Bool) {
    testCount += 1
    if condition {
        passCount += 1
        print("✓ \(name)")
    } else {
        print("✗ \(name)")
    }
}

// Chill stage tests
test("Stage.from(0%) == .chill", condition: Stage.from(percent: 0, thresholds: thresholds) == .chill)
test("Stage.from(39%) == .chill", condition: Stage.from(percent: 39, thresholds: thresholds) == .chill)

// Normal stage tests
test("Stage.from(40%) == .normal", condition: Stage.from(percent: 40, thresholds: thresholds) == .normal)
test("Stage.from(69%) == .normal", condition: Stage.from(percent: 69, thresholds: thresholds) == .normal)

// Busy stage tests
test("Stage.from(70%) == .busy", condition: Stage.from(percent: 70, thresholds: thresholds) == .busy)
test("Stage.from(84%) == .busy", condition: Stage.from(percent: 84, thresholds: thresholds) == .busy)

// Danger stage tests
test("Stage.from(85%) == .danger", condition: Stage.from(percent: 85, thresholds: thresholds) == .danger)
test("Stage.from(94%) == .danger", condition: Stage.from(percent: 94, thresholds: thresholds) == .danger)

// Burn stage tests
test("Stage.from(95%) == .burn", condition: Stage.from(percent: 95, thresholds: thresholds) == .burn)
test("Stage.from(100%) == .burn", condition: Stage.from(percent: 100, thresholds: thresholds) == .burn)
test("Stage.from(999%) == .burn", condition: Stage.from(percent: 999, thresholds: thresholds) == .burn)

// Animation interval tests
test("Stage.chill.animationIntervalSec == 0", condition: Stage.chill.animationIntervalSec == 0)
test("Stage.normal.animationIntervalSec == 0", condition: Stage.normal.animationIntervalSec == 0)
test("Stage.busy.animationIntervalSec == 2.0", condition: Stage.busy.animationIntervalSec == 2.0)
test("Stage.danger.animationIntervalSec == 1.0", condition: Stage.danger.animationIntervalSec == 1.0)
test("Stage.burn.animationIntervalSec == 0.5", condition: Stage.burn.animationIntervalSec == 0.5)

print("")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("Tests: \(passCount)/\(testCount) passed")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

if passCount == testCount {
    exit(0)
} else {
    exit(1)
}
