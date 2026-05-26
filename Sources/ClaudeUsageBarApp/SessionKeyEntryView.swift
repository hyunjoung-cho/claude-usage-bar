import AppKit
import SwiftUI

/// T14에서 SwiftUI paste 창 + Keychain 저장 흐름을 본격 구현합니다.
/// 현재(T12)는 NSLog 로 안내만 출력 — 사용자는 일단 콘솔/로그를 봅니다.
enum SessionKeyEntryView {
    static func present(_ onSubmit: @escaping (String) -> Void) {
        NSLog("[ClaudeUsageBar] 세션키 미등록 — T14 paste UI 구현 대기. " +
              "임시 우회 : 터미널에서 `security add-generic-password -s com.goldplat.claude-usage-bar -a claude-ai-session-key -w <YOUR_SESSION_KEY>` 실행 후 앱 재시작.")
        // onSubmit은 호출하지 않음 — T14에서 사용자 입력 받은 뒤 호출.
        _ = onSubmit
    }
}
