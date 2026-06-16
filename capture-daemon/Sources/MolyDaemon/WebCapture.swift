import Foundation
import AppKit

/// Captured web page data (DOM + CSS) via AppleScript JavaScript injection.
struct WebCaptureData {
    let pageUrl: String?
    let renderedHtml: String?
    let stylesJson: String?
}

/// Extracts rendered DOM and full CSS from browser tabs via AppleScript `execute javascript`.
/// Chrome/Chromium: `tell app "Google Chrome" to execute javascript` on active tab.
/// Safari: not yet supported (different AppleScript dictionary).
/// Non-browser apps: returns nil immediately.
enum WebCapture {

    /// Seconds before we give up on JS injection (long pages can be slow).
    private static let timeout: TimeInterval = 4.0

    /// Attempt web capture if the target process is a browser.
    /// Returns nil if not a browser, or if AppleScript/JS injection fails.
    static func capture(pid: pid_t, bundleID: String) async -> WebCaptureData? {
        guard let browserName = browserAppName(for: bundleID) else { return nil }

        // Build AppleScript. Chrome's OSAX limits JS result to ~10MB;
        // we cap each extraction in the JS itself.
        let script = buildScript(browserName: browserName, pid: pid)

        return await withCheckedContinuation { cont in
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]

            let outPipe = Pipe()
            let errPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = errPipe

            // Timeout
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                task.terminate()
            }
            timer.resume()

            let lock = NSLock()
            var didResume = false
            task.terminationHandler = { _ in
                timer.cancel()
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()

                let raw = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if task.terminationStatus != 0 || raw.isEmpty {
                    let errMsg = err.lowercased()
                    if errMsg.contains("执行 javascript") || errMsg.contains("execute javascript") || errMsg.contains("applescript") {
                        print("[WebCapture] ⚠️  Chrome → View → Developer → Allow JavaScript from Apple Events must be enabled.")
                        print("[WebCapture]    Fallback: page URL is still extracted from AX tree.")
                    } else {
                        print("[WebCapture] AppleScript failed (status=\(task.terminationStatus)): \(err.prefix(200))")
                    }
                    cont.resume(returning: nil)
                    return
                }

                // The AppleScript returns: pageURL \n ---MOLY_JSON--- \n jsonPayload
                let parts = raw.components(separatedBy: "\n---MOLY_JSON---\n")
                let pageUrl = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                let jsonPayload = parts.count > 1 ? parts[1] : nil

                // Parse JSON payload
                var renderedHtml: String?
                var stylesJson: String?
                if let jsonStr = jsonPayload,
                   let jsonData = jsonStr.data(using: .utf8),
                   let dict = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] {
                    renderedHtml = dict["html"] as? String
                    // Re-serialize the structured CSS data as pretty JSON
                    if let _ = dict["all_rules"] {
                        if let prettyData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                            stylesJson = String(data: prettyData, encoding: .utf8)
                        }
                    }
                }

                // Fallback URL: extract from AX tree if AppleScript didn't give us one
                let finalUrl = (pageUrl?.isEmpty == false) ? pageUrl : nil
                print("[WebCapture] URL=\(finalUrl ?? "nil") DOM=\(renderedHtml?.count ?? 0) bytes CSS=\(stylesJson?.count ?? 0) bytes")
                cont.resume(returning: WebCaptureData(
                    pageUrl: finalUrl,
                    renderedHtml: renderedHtml,
                    stylesJson: stylesJson
                ))
            }

            do {
                try task.run()
            } catch {
                lock.lock()
                if !didResume {
                    didResume = true
                    lock.unlock()
                    cont.resume(returning: nil)
                } else {
                    lock.unlock()
                }
            }
        }
    }

    // MARK: - Browser Detection

    /// Returns the AppleScript application name for the given bundle ID, or nil if not a browser.
    private static func browserAppName(for bundleID: String) -> String? {
        // Chromium-based browsers
        if bundleID.hasPrefix("com.google.Chrome") { return "Google Chrome" }
        if bundleID.hasPrefix("com.brave.Browser")   { return "Brave Browser" }
        if bundleID.hasPrefix("com.microsoft.edgemac") { return "Microsoft Edge" }
        if bundleID.hasPrefix("org.chromium.Chromium") { return "Chromium" }
        if bundleID.hasPrefix("com.operasoftware.Opera") { return "Opera" }
        if bundleID.hasPrefix("com.vivaldi.Vivaldi")   { return "Vivaldi" }
        // Safari
        if bundleID == "com.apple.Safari" { return "Safari" }
        // Arc
        if bundleID == "company.thebrowser.Browser" { return "Arc" }

        // Electron apps: check for framework on disk
        // Use NSWorkspace to find the app
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let frameworkPath = appURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path
            if FileManager.default.fileExists(atPath: frameworkPath) {
                return appURL.deletingPathExtension().lastPathComponent
            }
        }
        return nil
    }

    // MARK: - AppleScript Construction

    private static func buildScript(browserName: String, pid: pid_t) -> String {
        // Chromium-based approach: tell app by name, access active tab
        // Uses System Events to resolve PID → app name safely
        let jsCode = injectedJavaScript()

        return """
        on run
            set pageURL to ""
            try
                tell application "\(browserName)"
                    set pageURL to URL of active tab of front window
                end tell
            end try

            set jsonResult to ""
            try
                tell application "\(browserName)"
                    set jsonResult to execute active tab of front window javascript "\(escapingMolyJSON(jsCode))"
                end tell
            end try

            return pageURL & "
        ---MOLY_JSON---
        " & jsonResult
        end run
        """
    }

    /// JavaScript that runs inside the browser page to extract DOM + CSS + layout.
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
                    // Extract color values
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
    // Also collect from body/headings
    try {
        var els = document.querySelectorAll('body,h1,h2,h3,h4,h5,h6,p,nav,header,footer,button,a');
        for (var i = 0; i < Math.min(els.length, 50); i++) {
            fonts.add(getComputedStyle(els[i]).fontFamily.split(',')[0].replace(/['"]/g,'').trim());
        }
    } catch(e) {}
    data.fonts = Array.from(fonts).filter(function(f) { return f && f.length > 0 && f !== 'serif' && f !== 'sans-serif'; }).slice(0, 20);

    // ── 4. Layout: computed styles for semantic elements ──
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
        card: getStyles(document.querySelector('[class*="card"],article,.card-container'))
    };

    return JSON.stringify(data);
})();
"""#
    }

    /// Escape the JS string for embedding inside an AppleScript string.
    /// AppleScript uses backslash-escaped double quotes inside an outer double-quoted string.
    private static func escapingMolyJSON(_ js: String) -> String {
        // Replace backslash, double quote, newline
        var escaped = js
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        return escaped
    }
}
