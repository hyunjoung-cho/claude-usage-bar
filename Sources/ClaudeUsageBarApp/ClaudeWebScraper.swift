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

        // 3) /settings/usage 도달. 0.5초 대기 후 JS 평가 (redirect chain 안정화).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.evaluateScrapeJS(webView: webView)
        }
    }

    private func evaluateScrapeJS(webView: WKWebView) {
        let js = """
        new Promise((resolve) => {
            const deadline = Date.now() + 8000;
            const extract = () => {
                const text = (document.body && document.body.innerText) || '';
                if (/sign in|continue with|로그인/i.test(text) && !/used|사용/i.test(text)) {
                    resolve({ status: 'notLoggedIn' });
                    return;
                }
                const patterns = {
                    fiveHour: [
                        /5[\\s-]*hour[\\s\\S]{0,80}?(\\d+)\\s*%/i,
                        /(\\d+)\\s*%[\\s\\S]{0,40}?5[\\s-]*hour/i,
                        /(\\d+)\\s*%[\\s\\S]{0,40}?5시간/,
                        /5시간[\\s\\S]{0,40}?(\\d+)\\s*%/
                    ],
                    weekly: [
                        /week[ly]*[\\s\\S]{0,80}?(\\d+)\\s*%/i,
                        /(\\d+)\\s*%[\\s\\S]{0,40}?week[ly]*/i,
                        /주간[\\s\\S]{0,40}?(\\d+)\\s*%/,
                        /(\\d+)\\s*%[\\s\\S]{0,40}?주간/
                    ],
                    opus: [
                        /opus[\\s\\S]{0,80}?(\\d+)\\s*%/i,
                        /(\\d+)\\s*%[\\s\\S]{0,40}?opus/i
                    ]
                };
                const out = { fiveHour: null, weekly: null, opus: null };
                for (const [key, pats] of Object.entries(patterns)) {
                    for (const p of pats) {
                        const m = text.match(p);
                        if (m) { out[key] = parseInt(m[1]); break; }
                    }
                }
                if (out.fiveHour !== null) {
                    resolve({ status: 'ok', ...out });
                    return;
                }
                const anyPct = text.match(/(\\d+)\\s*%/);
                if (anyPct && Date.now() > deadline - 1000) {
                    resolve({ status: 'partial', fiveHour: parseInt(anyPct[1]), weekly: null, opus: null });
                    return;
                }
                if (Date.now() > deadline) {
                    resolve({ status: 'empty', dump: text.substring(0, 1000) });
                    return;
                }
                setTimeout(extract, 300);
            };
            setTimeout(extract, 300);
        });
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                guard let pending = self.pending else { return }

                switch result {
                case .success(let value):
                    NSLog("[scraper] JS success: \(String(describing: value).prefix(200))")
                    // JS Promise가 navigation away로 cancel되면 NSNull 또는 딕셔너리 캐스팅 실패
                    // → pending 유지, 다음 didFinish에서 재시도
                    guard let dict = value as? [String: Any] else {
                        if value is NSNull {
                            NSLog("[scraper] JS returned NSNull (navigation away) — keeping pending, waiting for next didFinish")
                        } else {
                            NSLog("[scraper] JS unexpected shape: \(String(describing: value).prefix(200)) — keeping pending")
                        }
                        return
                    }
                    guard let status = dict["status"] as? String else {
                        self.pending = nil
                        self.hardTimeoutWork?.cancel()
                        pending(.failure(.js("unexpected result shape: \(String(describing: value))")))
                        return
                    }
                    self.pending = nil
                    self.hardTimeoutWork?.cancel()
                    switch status {
                    case "notLoggedIn":
                        NSLog("[scraper] status=notLoggedIn")
                        pending(.failure(.notLoggedIn))
                    case "ok", "partial":
                        NSLog("[scraper] status=\(status), fiveHour=\(dict["fiveHour"] ?? "nil")")
                        let usage = ScrapedUsage(
                            fiveHourPercent: dict["fiveHour"] as? Int,
                            weeklyPercent:   dict["weekly"]   as? Int,
                            opusPercent:     dict["opus"]     as? Int
                        )
                        pending(.success(usage))
                    case "empty":
                        let dump = (dict["dump"] as? String) ?? ""
                        NSLog("[ClaudeUsageBar] scrape empty, page dump: \(dump.prefix(1000))")
                        pending(.failure(.domEmpty))
                    default:
                        pending(.failure(.js("unknown status: \(status)")))
                    }
                case .failure(let err):
                    NSLog("[scraper] JS error: \(err.localizedDescription)")
                    self.pending = nil
                    self.hardTimeoutWork?.cancel()
                    pending(.failure(.js(err.localizedDescription)))
                }
            }
        }
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
