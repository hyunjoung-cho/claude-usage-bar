import AppKit
import WebKit

/// claude.ai/settings/usage 페이지를 hidden WKWebView로 로드하여 사용량 %를 추출합니다.
/// 첫 실행 시 visible 윈도우로 로그인 페이지 노출 → 로그인 성공 후 hidden polling.
///
/// Cloudflare bot challenge는 진짜 브라우저(WKWebView)라 자동 통과.
@MainActor
final class ClaudeWebScraper: NSObject {
    private let webView: WKWebView
    private var loginWindow: NSWindow?
    private var pending: ((Result<ScrapedUsage, ScrapeError>) -> Void)?
    private var loadStartedAt: Date?
    private var hardTimeoutWork: DispatchWorkItem?

    /// 페이지에서 추출한 사용량.
    /// 우리가 잡을 수 있는 건 5h / weekly / opus 세 가지 %, 가능한 것만 채움.
    struct ScrapedUsage {
        let fiveHourPercent: Int?
        let weeklyPercent:   Int?
        let opusPercent:     Int?
    }

    enum ScrapeError: Error {
        case notLoggedIn
        case domEmpty           // DOM 로드는 됐는데 % 못 찾음
        case timeout
        case js(String)
        case navigation(String)
    }

    override init() {
        let config = WKWebViewConfiguration()
        // 영구 cookie/세션 저장 — 한 번 로그인하면 다음 실행도 유지
        // macOS 14+ : 명시적 영구 데이터스토어 (UUID 기반).
        // default() 는 LSUIElement 앱에서 비영속으로 동작할 수 있어서 cookie persistence 보장 안 됨.
        let storeID = UUID(uuidString: "B7E1A1F0-DA00-4C0F-AAAA-C1A4DE05A9E0")!
        if #available(macOS 14.0, *) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.default()
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), configuration: config)
        super.init()
        webView.navigationDelegate = self
        // 모바일 아닌 데스크탑 브라우저로 보이게
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    /// 사용자에게 로그인 윈도우를 노출합니다. 첫 실행 + 세션 만료 시.
    func showLoginWindow() {
        if loginWindow == nil {
            let vc = NSViewController()
            vc.view = webView
            let win = NSWindow(contentViewController: vc)
            win.title = "Claude Usage Bar — claude.ai 로그인"
            win.setContentSize(NSSize(width: 1000, height: 700))
            win.styleMask = [.titled, .closable, .resizable]
            win.center()
            win.isReleasedWhenClosed = false
            loginWindow = win
        }
        let url = URL(string: "https://claude.ai/login")!
        webView.load(URLRequest(url: url))
        NSApp.activate(ignoringOtherApps: true)
        loginWindow?.makeKeyAndOrderFront(nil)
    }

    func hideLoginWindow() {
        loginWindow?.orderOut(nil)
    }

    private func dumpCookies(tag: String) {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            let names = claudeCookies.map { $0.name }.sorted()
            NSLog("[scraper:\(tag)] claude.ai cookies count=\(claudeCookies.count) names=\(names.prefix(10))")
        }
    }

    /// 사용량 페이지를 한 번 scrape. polling 호출자가 60초마다 사용.
    func fetchOnce(completion: @escaping (Result<ScrapedUsage, ScrapeError>) -> Void) {
        NSLog("[scraper] fetchOnce called, current URL=\(webView.url?.absoluteString ?? "nil")")
        dumpCookies(tag: "before-fetch")
        guard pending == nil else {
            NSLog("[scraper] previous fetch still pending — returning .timeout")
            completion(.failure(.timeout))
            return
        }
        pending = completion
        loadStartedAt = Date()

        // 15초 hard timeout — didFinish 영원히 안 오는 경우 대비
        hardTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                guard let p = self.pending else { return }
                NSLog("[scraper] hard timeout 15s — pending released")
                self.pending = nil
                p(.failure(.timeout))
            }
        }
        hardTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)

        let url = URL(string: "https://claude.ai/settings/usage")!
        webView.load(URLRequest(url: url))
    }
}

extension ClaudeWebScraper: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlStr = webView.url?.absoluteString ?? ""
        NSLog("[scraper] didFinish navigation, URL=\(urlStr)")
        dumpCookies(tag: "didFinish")

        // 1) Login/sign-in 페이지로 도달 = 세션 없음. 즉시 notLoggedIn.
        let lower = urlStr.lowercased()
        if lower.contains("/login") || lower.contains("/sign-in") || lower.contains("/sign_in") || lower.contains("/oauth") {
            NSLog("[scraper] detected login page → notLoggedIn")
            guard let p = pending else { return }
            pending = nil
            hardTimeoutWork?.cancel()
            p(.failure(.notLoggedIn))
            return
        }

        // 2) /settings/usage 가 아닌 다른 페이지면 redirect 진행 중. 무시 + 다음 didFinish 기다림.
        if !lower.contains("/settings/usage") {
            NSLog("[scraper] interim navigation, waiting for next didFinish")
            return
        }

        // 3) /settings/usage 도달. 외부 polling으로 JS 평가 (SPA re-render 무관).
        evaluateScrapeJS(webView: webView)
    }

    private func evaluateScrapeJS(webView: WKWebView, attemptsLeft: Int = 16) {
        // 단순 동기 JS — Promise 없음, React 재렌더 영향 X
        let js = """
        (function() {
            const text = (document.body && document.body.innerText) || '';
            return text.substring(0, 5000);   // 첫 5KB만 — 충분
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            Task { @MainActor in
                let text = (result as? String) ?? ""

                // 로그인 페이지 감지
                if (text.lowercased().contains("sign in") || text.lowercased().contains("continue with") || text.contains("로그인"))
                    && !text.lowercased().contains("used") && !text.contains("사용") {
                    NSLog("[scraper] poll: login page text detected")
                    guard let p = self.pending else { return }
                    self.pending = nil
                    self.hardTimeoutWork?.cancel()
                    p(.failure(.notLoggedIn))
                    return
                }

                // 5h/weekly/opus % 추출
                let extracted = self.extractPercents(from: text)

                if extracted.fiveHour != nil || extracted.weekly != nil || extracted.opus != nil {
                    NSLog("[scraper] poll success: 5h=\(extracted.fiveHour ?? -1) weekly=\(extracted.weekly ?? -1) opus=\(extracted.opus ?? -1)")
                    // 첫 성공 사이클에서 page dump 파일 저장 — selector tuning용 (NSLog 1024자 제한 우회)
                    let dumpPath = NSHomeDirectory() + "/Library/Logs/ClaudeUsageBarPageDump.txt"
                    let dumpContent = "[scraper] page dump (first 3000ch) at \(Date()):\n\(text.prefix(3000))\n"
                    try? dumpContent.write(toFile: dumpPath, atomically: true, encoding: .utf8)
                    NSLog("[scraper] page dump saved → \(dumpPath)")
                    guard let p = self.pending else { return }
                    self.pending = nil
                    self.hardTimeoutWork?.cancel()
                    p(.success(ScrapedUsage(
                        fiveHourPercent: extracted.fiveHour,
                        weeklyPercent:   extracted.weekly,
                        opusPercent:     extracted.opus
                    )))
                    return
                }

                // 아직 % 못 찾음 — 재시도 또는 timeout
                if attemptsLeft > 0 {
                    // 0.5초 후 재시도, 최대 16회 = 8초
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.evaluateScrapeJS(webView: webView, attemptsLeft: attemptsLeft - 1)
                    }
                } else {
                    // 8초 폴링했는데도 % 없음 — DOM dump 후 fail
                    NSLog("[scraper] poll exhausted, page dump first 800ch: \(text.prefix(800))")
                    guard let p = self.pending else { return }
                    self.pending = nil
                    self.hardTimeoutWork?.cancel()
                    p(.failure(.domEmpty))
                }
            }
        }
    }

    private struct PercentExtraction {
        let fiveHour: Int?
        let weekly:   Int?
        let opus:     Int?
    }

    private func extractPercents(from text: String) -> PercentExtraction {
        // 정규식 매칭은 NSRegularExpression — Swift String.range(of:options:.regularExpression) 사용
        func match(_ pattern: String, in text: String) -> Int? {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let matched = String(text[range])
            // matched 안에서 첫 숫자% 추출
            if let pctRange = matched.range(of: #"(\d+)\s*%"#, options: .regularExpression) {
                let digits = matched[pctRange].filter { $0.isNumber }
                return Int(digits)
            }
            return nil
        }

        // 실제 claude.ai/settings/usage 페이지의 한국어 라벨 기반
        let fiveHourPatterns = [
            // "현재 세션" 라벨 → "X% 사용됨" — 5h block
            #"현재 세션[\s\S]{0,300}?\d+\s*%\s*사용됨"#,
            // 영어 fallback
            #"current session[\s\S]{0,300}?\d+\s*%"#
        ]
        let weeklyPatterns = [
            // "주간 한도" + "모든 모델" 라벨 → "X% 사용됨"
            #"주간 한도[\s\S]{0,100}?모든 모델[\s\S]{0,300}?\d+\s*%\s*사용됨"#,
            // 영어 fallback
            #"weekly[\s\S]{0,100}?all models[\s\S]{0,300}?\d+\s*%"#
        ]
        let opusPatterns = [
            // "Sonnet만" 라벨 → "X% 사용됨" — Opus 슬롯에 매핑 (페이지에 명시적 Opus 섹션 없음, Sonnet 한도가 대신)
            #"Sonnet만[\s\S]{0,300}?\d+\s*%\s*사용됨"#,
            // 영어 fallback
            #"Sonnet only[\s\S]{0,300}?\d+\s*%"#,
            // 진짜 opus 라벨이 있다면
            #"opus[\s\S]{0,100}?\d+\s*%"#
        ]

        func firstMatch(_ patterns: [String]) -> Int? {
            for p in patterns {
                if let v = match(p, in: text) { return v }
            }
            return nil
        }

        return PercentExtraction(
            fiveHour: firstMatch(fiveHourPatterns),
            weekly:   firstMatch(weeklyPatterns),
            opus:     firstMatch(opusPatterns)
        )
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[scraper] didFail navigation: \(error.localizedDescription)")
        hardTimeoutWork?.cancel()
        guard let p = pending else { return }
        pending = nil
        p(.failure(.navigation(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[scraper] didFailProvisional: \(error.localizedDescription)")
        // NSURLErrorCancelled (-999) = redirect chain 도중 이전 request가 취소됨.
        // 실제 실패가 아니므로 pending 유지, 다음 didFinish 기다림.
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            NSLog("[scraper] didFailProvisional -999 (redirect cancel) — keeping pending")
            return
        }
        hardTimeoutWork?.cancel()
        guard let p = pending else { return }
        pending = nil
        p(.failure(.navigation(error.localizedDescription)))
    }
}
