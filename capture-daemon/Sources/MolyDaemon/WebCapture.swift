import Foundation

/// Captured web page data (DOM + CSS) via Chrome DevTools Protocol.
struct WebCaptureData {
    let pageUrl: String?
    let renderedHtml: String?
    let stylesJson: String?
}

/// Extracts rendered DOM and full CSS from Chromium-based browsers
/// using Chrome DevTools Protocol (CDP) over WebSocket.
///
/// Requires: Chrome launched with `--remote-debugging-port=9222`
///           (handled by `molyd --setup` automatically)
///
/// No AppleScript, no Chrome "Allow JavaScript from Apple Events" needed.
enum WebCapture {

    private static let cdpHost = "127.0.0.1"
    private static let cdpPort = 9222
    private static let timeout: TimeInterval = 5.0

    // MARK: - Public API

    static func capture(pid: pid_t, bundleID: String) async -> WebCaptureData? {
        guard isChromiumBrowser(bundleID) else { return nil }
        guard await isCDPAvailable() else {
            print("[WebCapture] CDP port \(cdpPort) not available. Launch Chrome with --remote-debugging-port=\(cdpPort)")
            return nil
        }

        // 1. Get list of debuggable pages from CDP
        guard let pages = await fetchCDPPageList() else {
            print("[WebCapture] Failed to fetch CDP page list")
            return nil
        }

        // 2. Pick the active page (first in list is usually the frontmost tab)
        guard let target = pages.first else {
            print("[WebCapture] No debuggable pages found")
            return nil
        }

        let pageUrl = target["url"] as? String
        let pageTitle = target["title"] as? String
        guard let wsURL = target["webSocketDebuggerUrl"] as? String else {
            print("[WebCapture] No webSocketDebuggerUrl for page: \(pageTitle ?? "?")")
            return nil
        }

        // 3. Connect via WebSocket and run JS extraction
        guard let wsTask = connectWebSocket(wsURL) else {
            print("[WebCapture] WebSocket connection failed")
            return nil
        }

        // 4. Execute JavaScript to extract DOM + CSS
        let js = injectedJavaScript()
        guard let result = await evaluateJS(wsTask: wsTask, js: js) as? [String: Any] else {
            wsTask.cancel()
            print("[WebCapture] JS evaluation returned no result")
            return nil
        }

        wsTask.cancel()

        // 5. Parse result
        var renderedHtml: String?
        var stylesJson: String?

        if let html = result["html"] as? String, !html.isEmpty {
            renderedHtml = html
        }

        // Re-serialize CSS data as pretty JSON
        if let _ = result["all_rules"] {
            if let pretty = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: pretty, encoding: .utf8) {
                stylesJson = jsonStr
            }
        }

        print("[WebCapture] URL=\(pageUrl ?? "nil") DOM=\(renderedHtml?.count ?? 0) bytes CSS=\(stylesJson?.count ?? 0) bytes")
        return WebCaptureData(pageUrl: pageUrl, renderedHtml: renderedHtml, stylesJson: stylesJson)
    }

    // MARK: - CDP Communication

    private static func isCDPAvailable() async -> Bool {
        guard let url = URL(string: "http://\(cdpHost):\(cdpPort)/json/version") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return !data.isEmpty
        } catch {
            return false
        }
    }

    private static func fetchCDPPageList() async -> [[String: Any]]? {
        guard let url = URL(string: "http://\(cdpHost):\(cdpPort)/json") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 2.0)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        } catch {
            print("[WebCapture] CDP /json failed: \(error)")
            return nil
        }
    }

    private static func connectWebSocket(_ wsURLString: String) -> URLSessionWebSocketTask? {
        guard let url = URL(string: wsURLString) else { return nil }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        return task
    }

    private static func evaluateJS(wsTask: URLSessionWebSocketTask, js: String) async -> Any? {
        let cmd: [String: Any] = [
            "id": 1,
            "method": "Runtime.evaluate",
            "params": [
                "expression": js,
                "returnByValue": true,
                "timeout": 3000
            ]
        ]

        guard let cmdData = try? JSONSerialization.data(withJSONObject: cmd),
              let cmdStr = String(data: cmdData, encoding: .utf8) else { return nil }

        do {
            try await wsTask.send(.string(cmdStr))
        } catch {
            print("[WebCapture] send error: \(error)")
            return nil
        }

        // Receive with timeout
        do {
            let msg = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                group.addTask { try await wsTask.receive() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            guard case .string(let json) = msg,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            // CDP response: {"id":1,"result":{"result":{"type":"string","value":"..."}}}
            guard let cdpResult = dict["result"] as? [String: Any],
                  let innerResult = cdpResult["result"] as? [String: Any] else {
                return nil
            }

            // JS returns JSON.stringify(...) → it's a string value
            if let valueStr = innerResult["value"] as? String {
                if let valueData = valueStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: valueData) {
                    return obj
                }
            }
            // Fallback: the value might already be a dict (non-stringified)
            if let valueDict = innerResult["value"] as? [String: Any] {
                return valueDict
            }
            return nil
        } catch {
            print("[WebCapture] receive/timeout: \(error)")
            return nil
        }
    }

    // MARK: - Browser Detection

    private static func isChromiumBrowser(_ bundleID: String) -> Bool {
        if bundleID.hasPrefix("com.google.Chrome") { return true }
        if bundleID.hasPrefix("com.brave.Browser")   { return true }
        if bundleID.hasPrefix("com.microsoft.edgemac") { return true }
        if bundleID.hasPrefix("org.chromium.Chromium") { return true }
        if bundleID.hasPrefix("com.operasoftware.Opera") { return true }
        if bundleID.hasPrefix("com.vivaldi.Vivaldi")   { return true }
        return false
    }

    // MARK: - JavaScript Injection Payload

    private static func injectedJavaScript() -> String {
        return #"""
(function(){
    var data = {};
    var MAX_DOM = 500000;
    var MAX_RULES = 500;
    var MAX_RULE_LEN = 2000;

    // ── 1. DOM ──
    try {
        data.html = document.documentElement.outerHTML.substring(0, MAX_DOM);
    } catch(e) {
        data.html = "";
    }

    // ── 2. CSS rules + colors ──
    var rules = [];
    var colors = new Set();
    var fonts = new Set();
    try {
        for (var i = 0; i < document.styleSheets.length && rules.length < MAX_RULES; i++) {
            var sheet = document.styleSheets[i];
            try {
                for (var j = 0; j < sheet.cssRules.length && rules.length < MAX_RULES; j++) {
                    var rule = sheet.cssRules[j];
                    var cssText = (rule.cssText || '').substring(0, MAX_RULE_LEN);
                    var selector = rule.selectorText || rule.type?.toString() || '';
                    rules.push({ selector: selector, cssText: cssText });
                    var matches = cssText.match(/#[0-9a-fA-F]{3,8}\b|rgba?\([^)]+\)|hsla?\([^)]+\)/g) || [];
                    matches.forEach(function(c) { colors.add(c); });
                }
            } catch(e) {}
        }
    } catch(e) {}
    data.all_rules = rules;
    data.palette = Array.from(colors).slice(0, 200);

    // ── 3. Fonts ──
    try {
        document.fonts.forEach(function(f) { fonts.add(f.family); });
    } catch(e) {}
    try {
        var els = document.querySelectorAll('body,h1,h2,h3,h4,h5,h6,p,nav,header,footer,button,a');
        for (var i = 0; i < Math.min(els.length, 50); i++) {
            fonts.add(getComputedStyle(els[i]).fontFamily.split(',')[0].replace(/['"]/g,'').trim());
        }
    } catch(e) {}
    data.fonts = Array.from(fonts).filter(function(f) { return f && f.length > 0 && f !== 'serif' && f !== 'sans-serif'; }).slice(0, 20);

    // ── 4. Layout stamps ──
    function getStyles(el) {
        if (!el) return {};
        var s = getComputedStyle(el);
        return {
            'background-color': s.backgroundColor,
            'color': s.color,
            'font-family': s.fontFamily,
            'font-size': s.fontSize,
            'font-weight': s.fontWeight,
            'line-height': s.lineHeight,
            'letter-spacing': s.letterSpacing,
            'border-radius': s.borderRadius,
            'border': s.border,
            'padding': s.padding,
            'margin': s.margin,
            'display': s.display,
            'position': s.position,
            'flex-direction': s.flexDirection,
            'gap': s.gap,
            'max-width': s.maxWidth,
            'text-transform': s.textTransform
        };
    }
    data.layout = {
        body: getStyles(document.body),
        nav: getStyles(document.querySelector('nav,header,[class*="nav"],[class*="header"]')),
        h1: getStyles(document.querySelector('h1')),
        h2: getStyles(document.querySelector('h2')),
        button: getStyles(document.querySelector('button,.btn,[class*="button"],a[class*="btn"]')),
        card: getStyles(document.querySelector('[class*="card"],article'))
    };

    return JSON.stringify(data);
})();
"""#
    }
}
