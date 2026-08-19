import AppKit
import WebKit

/// claude.ai/settings/usage 를 hidden WKWebView로 로드하여 사용량 %를 추출합니다.
///
/// 🟢 2026-07-22 : DOM 텍스트 정규식(한국어 라벨 의존) → **JSON API 직접 사용**으로 전환.
///   사용량 페이지는 `/api/organizations/{org}/usage` 를 스스로 호출합니다.
///   그 fetch 응답을 documentStart 훅으로 가로채(`window.__usageBody`) 그대로 파싱합니다.
///   → claude.ai가 화면(라벨/DOM)을 바꿔도 안 깨짐. org UUID 하드코딩 없음(앱이 쓰는 URL을 그대로 따라감).
///   DOM 정규식은 API를 못 잡았을 때의 **최후 fallback**으로만 남겨둡니다.
///
/// Cloudflare bot challenge는 진짜 브라우저(WKWebView)라 자동 통과.
@MainActor
final class ClaudeWebScraper: NSObject {
    private var webView: WKWebView
    private var loginWindow: NSWindow?
    private var pending: ((Result<ScrapedUsage, ScrapeError>) -> Void)?
    private var loadStartedAt: Date?
    private var hardTimeoutWork: DispatchWorkItem?
    /// 백지 페이지(JS 미실행) 연속 횟수. 2회면 웹뷰를 통째로 재생성한다.
    private var blankStreak = 0

    /// 페이지/ API에서 추출한 사용량. 가능한 것만 채움.
    struct ScrapedUsage {
        let fiveHourPercent: Int?
        let weeklyPercent:   Int?
        let opusPercent:     Int?
        let fiveHourResetSec: Int?       // 5h block reset까지 남은 초
    }

    enum ScrapeError: Error {
        case notLoggedIn
        case domEmpty           // 로드는 됐는데 API도 DOM도 데이터 없음
        case timeout
        case js(String)
        case navigation(String)
    }

    /// 웹뷰 1개를 규격대로 생성. 재생성(자가복구) 때도 이 팩토리를 그대로 쓴다.
    /// 데이터스토어 UUID가 고정이라 재생성해도 로그인 쿠키는 유지된다.
    private static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // 영구 cookie/세션 저장 — 한 번 로그인하면 다음 실행도 유지.
        // default() 는 LSUIElement 앱에서 비영속으로 동작할 수 있어 명시적 UUID 데이터스토어 사용.
        let storeID = UUID(uuidString: "B7E1A1F0-DA00-4C0F-AAAA-C1A4DE05A9E0")!
        if #available(macOS 14.0, *) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.default()
        }

        // 🟢 사용량 API 훅 : 페이지가 부르는 `/api/organizations/{org}/usage` 응답을 가로채 저장.
        //   - forMainFrameOnly:false 로 모든 프레임 커버, documentStart 로 fetch 재정의보다 먼저 주입.
        //   - 쿼리 제거 후 경로가 `/usage` 로 끝나는 organizations 호출만 매칭(usage_cost 등 오매칭 방지).
        let usageHook = """
        (function(){
            if (window.__usageHooked) return; window.__usageHooked = true;
            window.__netlog = [];
            function note(url){
                try {
                    if (typeof url !== 'string') return;
                    if (url.indexOf('/api/') === -1) return;
                    if (window.__netlog.length < 60) window.__netlog.push(url.split('?')[0]);
                } catch(e){}
            }
            function isUsage(url){
                if (typeof url !== 'string') return false;
                var clean = url.split('?')[0];
                return clean.indexOf('/api/organizations/') !== -1 && clean.slice(-6) === '/usage';
            }
            var of = window.fetch;
            window.fetch = function(){
                var a = arguments[0];
                var url = (a && a.url) || a;
                var pr = of.apply(this, arguments);
                try {
                    note(url);
                    if (isUsage(url)) {
                        window.__usageUrl = url;
                        pr.then(function(r){
                            try { r.clone().text().then(function(t){ window.__usageBody = t; }); } catch(e){}
                        }).catch(function(){});
                    }
                } catch(e){}
                return pr;
            };
            // XHR도 후킹 — 페이지가 fetch 대신 XHR로 부르는 경우 대비
            try {
                var oo = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(m, u){
                    try {
                        note(u);
                        if (isUsage(u)) {
                            window.__usageUrl = u;
                            this.addEventListener('load', function(){
                                try { window.__usageBody = this.responseText; } catch(e){}
                            });
                        }
                    } catch(e){}
                    return oo.apply(this, arguments);
                };
            } catch(e){}
        })();
        """
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: usageHook, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = ucc

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), configuration: config)
        // 모바일 아닌 데스크탑 브라우저로 보이게
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        return wv
    }

    override init() {
        webView = Self.makeWebView()
        super.init()
        webView.navigationDelegate = self
    }

    /// 🔴 자가복구 — 웹뷰가 죽어(백지·JS 미실행) 다시 못 살아나는 상태에서 통째로 재생성한다.
    ///
    /// 실측(2026-08-19) : 맥 절전 → 깨어남 직후 `didFailProvisional: offline` 이후로
    /// 매 로드가 didFinish는 오는데 페이지가 완전 백지(innerText 0, /api/ 호출 0건, userScript 미실행).
    /// 프로세스를 재시작하면 즉시 정상 → 웹뷰 프로세스만 죽은 것. 앱엔 복구 경로가 없어 몇 시간씩 ❓ 였다.
    private func rebuildWebView(reason: String) {
        NSLog("[scraper] 🔄 웹뷰 재생성 — 이유: \(reason)")
        let old = webView
        old.navigationDelegate = nil
        old.stopLoading()

        let fresh = Self.makeWebView()
        fresh.navigationDelegate = self
        webView = fresh
        blankStreak = 0

        // 로그인 윈도우가 떠 있으면 새 웹뷰로 교체(옛 웹뷰는 죽어 있어 화면도 백지)
        if let win = loginWindow, let vc = win.contentViewController {
            vc.view = fresh
        }
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

        let lower = urlStr.lowercased()
        // 1) Login/sign-in 페이지로 도달 = 세션 없음.
        if lower.contains("/login") || lower.contains("/sign-in") || lower.contains("/sign_in") || lower.contains("/oauth") {
            NSLog("[scraper] detected login page → notLoggedIn")
            finish(.failure(.notLoggedIn))
            return
        }
        // 2) /settings/usage 가 아닌 다른 페이지면 redirect 진행 중. 다음 didFinish 기다림.
        if !lower.contains("/settings/usage") {
            NSLog("[scraper] interim navigation, waiting for next didFinish")
            return
        }
        // 3) 도달. 외부 Swift polling으로 API 응답(window.__usageBody)을 기다림.
        pollUsage(webView: webView)
    }

    private func finish(_ result: Result<ScrapedUsage, ScrapeError>) {
        guard let p = pending else { return }
        pending = nil
        hardTimeoutWork?.cancel()
        p(result)
    }

    /// window.__usageBody(가로챈 API 응답)를 0.5초 × 16회(=8초) 폴링.
    /// - body 있으면 JSON 파싱 → 성공
    /// - url만 있고 body 없으면 능동 re-fetch 1회 kick 후 계속 폴링
    /// - 둘 다 없으면 DOM 정규식 fallback 시도
    private func pollUsage(webView: WKWebView, attemptsLeft: Int = 16, refetchKicked: Bool = false) {
        let js = """
        (function(){
            var text = '';
            try { text = ((document.body && document.body.innerText) || '').substring(0, 8000); } catch(e){}
            var html = '';
            try { html = (document.documentElement && document.documentElement.innerHTML) || ''; } catch(e){}
            return JSON.stringify({
                body: window.__usageBody || null,
                url:  window.__usageUrl || null,
                text: text,
                diag: {
                    href: location.href,
                    title: document.title,
                    ready: document.readyState,
                    htmlLen: html.length,
                    htmlHead: html.substring(0, 1200),
                    net: window.__netlog || [],
                    hooked: !!window.__usageHooked
                }
            });
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            Task { @MainActor in
                let raw = (result as? String) ?? ""
                let parsed = self.parseOuter(raw)
                let usageBody = parsed.body
                let usageUrl  = parsed.url
                let pageText  = parsed.text

                // 로그인 페이지 감지 (텍스트 기반)
                let lt = pageText.lowercased()
                if (lt.contains("sign in") || lt.contains("continue with") || pageText.contains("로그인"))
                    && !lt.contains("used") && !pageText.contains("사용") && usageBody == nil {
                    NSLog("[scraper] poll: login page text detected")
                    self.finish(.failure(.notLoggedIn))
                    return
                }

                // A) 가로챈 API 응답 있으면 JSON 파싱
                if let body = usageBody, let usage = self.parseUsageJSON(body) {
                    NSLog("[scraper] API success: 5h=\(usage.fiveHourPercent ?? -1) weekly=\(usage.weeklyPercent ?? -1) opus=\(usage.opusPercent ?? -1) resetSec=\(usage.fiveHourResetSec ?? -1)")
                    let dumpPath = NSHomeDirectory() + "/Library/Logs/ClaudeUsageBarApiDump.txt"
                    try? "API dump at \(Date()):\n\(body.prefix(4000))\n".write(toFile: dumpPath, atomically: true, encoding: .utf8)
                    self.blankStreak = 0
                    self.finish(.success(usage))
                    return
                }

                // B) url만 있고 body 없으면 능동 re-fetch 1회 (race 대비)
                if usageBody == nil, usageUrl != nil, !refetchKicked {
                    let kick = """
                    (function(){
                        if (!window.__usageUrl || window.__refetching) return 'skip';
                        window.__refetching = true;
                        fetch(window.__usageUrl, {credentials:'include', headers:{'accept':'application/json'}})
                          .then(function(r){ return r.text(); })
                          .then(function(t){ window.__usageBody = t; window.__refetching = false; })
                          .catch(function(){ window.__refetching = false; });
                        return 'kicked';
                    })();
                    """
                    webView.evaluateJavaScript(kick) { _, _ in }
                    if attemptsLeft > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.pollUsage(webView: webView, attemptsLeft: attemptsLeft - 1, refetchKicked: true)
                        }
                        return
                    }
                }

                // C) 계속 재시도
                if attemptsLeft > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.pollUsage(webView: webView, attemptsLeft: attemptsLeft - 1, refetchKicked: refetchKicked)
                    }
                    return
                }

                // D) 최후 fallback : DOM 정규식 (API를 끝내 못 잡은 경우)
                let ext = self.extractPercents(from: pageText)
                if ext.fiveHour != nil || ext.weekly != nil || ext.opus != nil {
                    NSLog("[scraper] DOM fallback success: 5h=\(ext.fiveHour ?? -1) weekly=\(ext.weekly ?? -1)")
                    self.blankStreak = 0
                    let resetSec = self.extractFiveHourResetSec(from: pageText)
                    self.finish(.success(ScrapedUsage(
                        fiveHourPercent: ext.fiveHour,
                        weeklyPercent:   ext.weekly,
                        opusPercent:     ext.opus,
                        fiveHourResetSec: resetSec
                    )))
                    return
                }

                NSLog("[scraper] poll exhausted — no API body, no DOM match. urlSeen=\(usageUrl != nil) textLen=\(pageText.count)")
                self.writeDiag(parsed.diag)

                // 🔴 백지(=userScript조차 안 돈 죽은 웹뷰) 판정 → 2회 연속이면 웹뷰 재생성
                let htmlLen = (parsed.diag["htmlLen"] as? Int) ?? 0
                let hooked  = (parsed.diag["hooked"] as? Bool) ?? false
                if !hooked || htmlLen < 500 {
                    self.blankStreak += 1
                    NSLog("[scraper] 백지 감지 (\(self.blankStreak)회 연속) hooked=\(hooked) htmlLen=\(htmlLen)")
                    if self.blankStreak >= 2 {
                        self.rebuildWebView(reason: "백지 페이지 2회 연속 — 웹뷰 사망 판정")
                    }
                } else {
                    self.blankStreak = 0
                }

                self.finish(.failure(.domEmpty))
            }
        }
    }

    // MARK: - JSON 파싱

    private struct Outer { let body: String?; let url: String?; let text: String; let diag: [String: Any] }

    private func parseOuter(_ raw: String) -> Outer {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Outer(body: nil, url: nil, text: "", diag: [:])
        }
        return Outer(
            body: obj["body"] as? String,
            url:  obj["url"]  as? String,
            text: (obj["text"] as? String) ?? "",
            diag: (obj["diag"] as? [String: Any]) ?? [:]
        )
    }

    /// 실패 시점의 페이지 실제 상태를 파일로 덤프. 원인(세션만료/CF차단/엔드포인트 변경) 판별용.
    private func writeDiag(_ diag: [String: Any]) {
        let net = (diag["net"] as? [String]) ?? []
        let lines = """
        === ClaudeUsageBar DIAG \(Date()) ===
        href      : \(diag["href"] as? String ?? "?")
        title     : \(diag["title"] as? String ?? "?")
        readyState: \(diag["ready"] as? String ?? "?")
        hookAlive : \(diag["hooked"] as? Bool ?? false)
        htmlLen   : \(diag["htmlLen"] as? Int ?? -1)
        /api/ 호출 \(net.count)건:
        \(net.map { "  - " + $0 }.joined(separator: "\n"))
        --- html head 1200 ---
        \(diag["htmlHead"] as? String ?? "")
        """
        let path = NSHomeDirectory() + "/Library/Logs/ClaudeUsageBarDiag.txt"
        try? lines.write(toFile: path, atomically: true, encoding: .utf8)
        NSLog("[scraper] DIAG written: href=\(diag["href"] as? String ?? "?") htmlLen=\(diag["htmlLen"] as? Int ?? -1) apiCalls=\(net.count) hooked=\(diag["hooked"] as? Bool ?? false)")
    }

    /// `/api/organizations/{org}/usage` 응답 JSON → ScrapedUsage.
    private func parseUsageJSON(_ body: String) -> ScrapedUsage? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // "five_hour" / "seven_day" / "seven_day_opus" 각각 { utilization: Double, resets_at: String }
        func utilization(_ key: String) -> Int? {
            guard let d = obj[key] as? [String: Any] else { return nil }
            if let u = d["utilization"] as? Double { return Int(u.rounded()) }
            if let n = d["utilization"] as? NSNumber { return Int(n.doubleValue.rounded()) }
            return nil
        }
        func resetsAt(_ key: String) -> Int? {
            guard let d = obj[key] as? [String: Any], let iso = d["resets_at"] as? String else { return nil }
            return Self.secondsUntil(iso)
        }

        let five   = utilization("five_hour")
        let weekly = utilization("seven_day")
        let opus   = utilization("seven_day_opus")   // 대개 null → nil (정직한 미표시)

        // 하나도 못 뽑으면 유효하지 않은 응답
        if five == nil && weekly == nil && opus == nil { return nil }

        return ScrapedUsage(
            fiveHourPercent: five,
            weeklyPercent:   weekly,
            opusPercent:     opus,
            fiveHourResetSec: resetsAt("five_hour")
        )
    }

    /// ISO8601 문자열(마이크로초·타임존 포함) → 지금부터 남은 초(음수면 0).
    private static func secondsUntil(_ iso: String) -> Int? {
        // "2026-07-22T05:30:00.005309+00:00" — ISO8601DateFormatter는 소수 6자리에서 실패할 수 있어
        // 소수부(.NNNNNN)를 제거한 뒤 파싱.
        let trimmed = iso.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression
        )
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let date = fmt.date(from: trimmed) else { return nil }
        return max(0, Int(date.timeIntervalSinceNow))
    }

    // MARK: - DOM 정규식 fallback (API 실패 시에만)

    private struct PercentExtraction { let fiveHour: Int?; let weekly: Int?; let opus: Int? }

    private func extractPercents(from text: String) -> PercentExtraction {
        func match(_ pattern: String, in text: String) -> Int? {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let matched = String(text[range])
            if let pctRange = matched.range(of: #"(\d+)\s*%"#, options: .regularExpression) {
                let digits = matched[pctRange].filter { $0.isNumber }
                return Int(digits)
            }
            return nil
        }
        let fiveHourPatterns = [
            #"현재 세션[\s\S]{0,300}?\d+\s*%\s*사용됨"#,
            #"current session[\s\S]{0,300}?\d+\s*%"#
        ]
        let weeklyPatterns = [
            #"주간 한도[\s\S]{0,600}?모든 모델[\s\S]{0,300}?\d+\s*%\s*사용됨"#,
            #"weekly[\s\S]{0,600}?all models[\s\S]{0,300}?\d+\s*%"#
        ]
        let opusPatterns = [
            #"Sonnet만[\s\S]{0,300}?\d+\s*%\s*사용됨"#,
            #"Sonnet only[\s\S]{0,300}?\d+\s*%"#,
            #"opus[\s\S]{0,100}?\d+\s*%"#
        ]
        func firstMatch(_ patterns: [String]) -> Int? {
            for p in patterns { if let v = match(p, in: text) { return v } }
            return nil
        }
        return PercentExtraction(
            fiveHour: firstMatch(fiveHourPatterns),
            weekly:   firstMatch(weeklyPatterns),
            opus:     firstMatch(opusPatterns)
        )
    }

    private func extractFiveHourResetSec(from text: String) -> Int? {
        let scopePattern = #"현재 세션[\s\S]{0,300}?재설정"#
        guard let scopeRange = text.range(of: scopePattern, options: [.regularExpression]) else { return nil }
        let scope = String(text[scopeRange])
        if let m = scope.range(of: #"(\d+)\s*시간\s*(\d+)\s*분"#, options: .regularExpression) {
            let nums = String(scope[m]).components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if nums.count >= 2 { return nums[0] * 3600 + nums[1] * 60 }
        }
        if let m = scope.range(of: #"(\d+)\s*시간"#, options: .regularExpression) {
            if let n = String(scope[m]).components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first {
                return n * 3600
            }
        }
        if let m = scope.range(of: #"(\d+)\s*분"#, options: .regularExpression) {
            if let n = String(scope[m]).components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first {
                return n * 60
            }
        }
        return nil
    }

    /// 웹콘텐츠 프로세스가 죽으면 WebKit이 알려준다. 이때 즉시 재생성하지 않으면
    /// 이후 모든 로드가 백지로 "성공"해 위젯이 ❓ 상태로 굳는다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[scraper] ⚠️ 웹콘텐츠 프로세스 종료 감지 — 즉시 재생성")
        finish(.failure(.timeout))
        rebuildWebView(reason: "웹콘텐츠 프로세스 종료 통지")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[scraper] didFail navigation: \(error.localizedDescription)")
        finish(.failure(.navigation(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[scraper] didFailProvisional: \(error.localizedDescription)")
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
            NSLog("[scraper] didFailProvisional -999 (redirect cancel) — keeping pending")
            return
        }
        finish(.failure(.navigation(error.localizedDescription)))
    }
}
