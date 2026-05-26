import Foundation
import Security

/// Keychain 작업 중 발생할 수 있는 에러.
public enum KeychainError: Error, Equatable {
    case saveFailed(OSStatus)
}

/// Claude AI 세션키를 macOS Keychain에 안전하게 저장/꺼내기/삭제하는 관리자.
///
/// - Note: macOS CLI 툴이 Keychain에 **처음** 접근할 때
///   "Always Allow / Deny" 시스템 팝업이 뜰 수 있습니다.
///   "Always Allow"를 한 번 클릭하면 이후 자동 허용됩니다.
///   (코드 서명 없이는 프로그래매틱하게 억제할 수 없습니다.)
public final class SessionKeyManager {
    private let service: String
    private let account = "claude-ai-session-key"

    public init(service: String = "com.goldplat.claude-usage-bar") {
        self.service = service
    }

    /// Keychain에 저장된 세션키를 가져옵니다. 없으면 `nil`.
    public func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 세션키를 Keychain에 저장합니다. 같은 service/account 항목이 있으면 덮어씁니다.
    public func save(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.saveFailed(errSecParam)
        }
        let baseQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        // 기존 항목을 먼저 삭제해야 덮어쓰기가 됩니다 (SecItemUpdate 대신 delete+add 패턴).
        SecItemDelete(baseQuery as CFDictionary)
        var addQuery = baseQuery
        addQuery[kSecValueData] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Keychain에서 세션키를 제거합니다. 존재하지 않더라도 에러를 던지지 않습니다.
    public func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
