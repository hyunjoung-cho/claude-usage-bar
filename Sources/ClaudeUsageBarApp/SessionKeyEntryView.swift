import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// 첫 실행 또는 세션키 재등록 시 표시되는 paste 창.
/// 사용자가 claude.ai sessionKey를 붙여넣고 "저장"을 누르면 onSubmit 호출.
@MainActor
enum SessionKeyEntryView {
    private static var window: NSWindow?

    static func present(_ onSubmit: @escaping (String) -> Void) {
        // 이미 열려있으면 앞으로 가져오기만
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SessionKeyEntryRootView(
            onSubmit: { key in
                onSubmit(key)
                Self.close()
            },
            onCancel: { Self.close() }
        )
        let hosting = NSHostingController(rootView: rootView)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Claude Usage Bar — 세션키 등록"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 480, height: 320))
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

private struct SessionKeyEntryRootView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var key: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("claude.ai 세션키 등록")
                .font(.title2)
                .fontWeight(.bold)

            Text("""
            1. claude.ai에 로그인된 브라우저에서 Cmd+Opt+I (개발자 도구)
            2. Application → Cookies → https://claude.ai
            3. `sessionKey` 값 복사
            4. 아래 칸에 붙여넣기
            """)
            .font(.callout)
            .foregroundColor(.secondary)

            TextField("sessionKey 붙여넣기", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
