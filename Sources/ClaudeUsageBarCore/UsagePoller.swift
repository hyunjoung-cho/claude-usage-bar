import Foundation

public final class UsagePoller {
    private let keyManager: SessionKeyManager
    private let session: URLSession
    private let endpoint: URL

    public var onUpdate: ((UsageData) -> Void)?
    public var onError:  ((PollError) -> Void)?

    private var timer: Timer?

    public init(
        keyManager: SessionKeyManager,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://claude.ai/api/account/usage")!
    ) {
        self.keyManager = keyManager
        self.session = session
        self.endpoint = endpoint
    }

    public func start(intervalSec: Int) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSec), repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
        Task { await tick() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        let result = await fetchOnce()
        switch result {
        case .success(let usage): onUpdate?(usage)
        case .failure(let err):   onError?(err)
        }
    }

    /// API를 한 번 호출하여 UsageData 또는 에러를 반환합니다.
    /// 네트워크/스키마/세션키 오류를 모두 `PollError`로 매핑합니다.
    public func fetchOnce() async -> Result<UsageData, PollError> {
        guard let key = keyManager.load() else {
            return .failure(.noSessionKey)
        }
        var request = URLRequest(url: endpoint)
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                return .failure(.sessionExpired)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let usage = try decoder.decode(UsageData.self, from: data)
                return .success(usage)
            } catch {
                return .failure(.schemaChanged(String(describing: error)))
            }
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
