import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// 컷오프 / 폴링 주기 / 세션키 재등록을 위한 설정 창.
/// AppDelegate가 `SettingsView.present(...)`를 호출.
@MainActor
enum SettingsView {
    private static var window: NSWindow?

    static func present(
        current: Config,
        onSave: @escaping (Config) -> Void,
        onResetSessionKey: @escaping () -> Void
    ) {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsRootView(
            initial: current,
            onSave: { updated in
                onSave(updated)
                Self.close()
            },
            onResetSessionKey: {
                onResetSessionKey()
                Self.close()
            },
            onCancel: { Self.close() }
        )
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Claude Usage Bar — 설정"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 480, height: 460))
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct SettingsRootView: View {
    let initial: Config
    let onSave: (Config) -> Void
    let onResetSessionKey: () -> Void
    let onCancel: () -> Void

    @State private var chillMax: Double
    @State private var normalMax: Double
    @State private var busyMax: Double
    @State private var dangerMax: Double
    @State private var pollIntervalSec: Double
    @State private var showPercent: Bool
    @State private var showTimeLeft: Bool

    init(
        initial: Config,
        onSave: @escaping (Config) -> Void,
        onResetSessionKey: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.onSave = onSave
        self.onResetSessionKey = onResetSessionKey
        self.onCancel = onCancel
        _chillMax = State(initialValue: Double(initial.thresholds.chillMax))
        _normalMax = State(initialValue: Double(initial.thresholds.normalMax))
        _busyMax = State(initialValue: Double(initial.thresholds.busyMax))
        _dangerMax = State(initialValue: Double(initial.thresholds.dangerMax))
        _pollIntervalSec = State(initialValue: Double(initial.pollIntervalSec))
        _showPercent = State(initialValue: initial.showPercentInMenubar)
        _showTimeLeft = State(initialValue: initial.showTimeLeftInMenubar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("설정")
                .font(.title2)
                .fontWeight(.bold)

            // 컷오프
            VStack(alignment: .leading, spacing: 6) {
                Text("단계별 컷오프 (%)")
                    .font(.headline)
                thresholdRow("여유 → 보통",   value: $chillMax,  range: 0...100)
                thresholdRow("보통 → 임박",   value: $normalMax, range: 0...100)
                thresholdRow("임박 → 위험",   value: $busyMax,   range: 0...100)
                thresholdRow("위험 → 불탐",   value: $dangerMax, range: 0...100)
            }

            Divider()

            // 폴링 주기
            VStack(alignment: .leading, spacing: 6) {
                Text("새로고침 주기 (초)")
                    .font(.headline)
                HStack {
                    Slider(value: $pollIntervalSec, in: 10...300, step: 10)
                    Text("\(Int(pollIntervalSec))s")
                        .frame(width: 50, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            Divider()

            // 표시 옵션
            VStack(alignment: .leading, spacing: 6) {
                Text("메뉴바 표시")
                    .font(.headline)
                Toggle("퍼센트 표시", isOn: $showPercent)
                Toggle("남은 시간 표시", isOn: $showTimeLeft)
            }

            Divider()

            // 세션키 재등록
            Button("🔑 세션키 재등록…", action: onResetSessionKey)

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    var updated = initial
                    updated.thresholds = Thresholds(
                        chillMax:  Int(chillMax),
                        normalMax: Int(normalMax),
                        busyMax:   Int(busyMax),
                        dangerMax: Int(dangerMax)
                    )
                    updated.pollIntervalSec = Int(pollIntervalSec)
                    updated.showPercentInMenubar = showPercent
                    updated.showTimeLeftInMenubar = showTimeLeft
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func thresholdRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 120, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))%")
                .frame(width: 50, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
