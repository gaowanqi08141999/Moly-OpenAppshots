import Foundation

/// Captured web page URL from AX tree.
/// CSS/DOM extraction is left to the agent — it has HTTP capabilities and can curl any URL.
/// This keeps Moly lightweight and avoids fragile headless Chrome management.
struct WebCaptureData {
    let pageUrl: String?
    let renderedHtml: String?
    let stylesJson: String?
}

/// Extracts the page URL from browser AX trees for agent use.
/// The agent uses this URL to curl CSS/DOM when needed.
enum WebCapture {

    static func capture(pid: pid_t, bundleID: String, pageURL: String?) async -> WebCaptureData? {
        guard isChromiumBrowser(bundleID),
              let url = pageURL,
              url.hasPrefix("http") else { return nil }
        return WebCaptureData(pageUrl: url, renderedHtml: nil, stylesJson: nil)
    }

    private static func isChromiumBrowser(_ bundleID: String) -> Bool {
        return bundleID.hasPrefix("com.google.Chrome") ||
               bundleID.hasPrefix("com.brave.Browser") ||
               bundleID.hasPrefix("com.microsoft.edgemac") ||
               bundleID.hasPrefix("org.chromium.Chromium")
    }
}
