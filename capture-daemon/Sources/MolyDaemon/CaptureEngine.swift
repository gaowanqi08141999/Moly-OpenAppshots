import Cocoa
import ScreenCaptureKit
import ApplicationServices

/// Dual-layer capture engine:
///   1. ScreenCaptureKit → high-fidelity PNG screenshot of the frontmost window
///   2. Accessibility API → structured text tree (visible + off-screen content)
final class CaptureEngine: @unchecked Sendable {

    // MARK: - Public API

    /// Capture the frontmost window: screenshot + accessibility tree.
    func captureFrontmost() async throws -> CaptureResult {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw CaptureError.noActiveApp
        }
        return try await captureApp(pid: frontApp.processIdentifier)
    }

    /// Capture a specific app by PID (used by hotkey to avoid focus-stealing issues).
    func captureApp(pid: pid_t) async throws -> CaptureResult {
        // NSRunningApplication(pid:) may return nil for some processes (Chrome renderers, etc).
        // Fall back to NSWorkspace → ps → process name.
        let frontApp = NSRunningApplication(processIdentifier: pid)
        let appName: String
        let bundleID: String
        if let app = frontApp {
            appName = app.localizedName ?? resolveProcessName(pid)
            bundleID = app.bundleIdentifier ?? "unknown"
        } else {
            // Chrome main process sometimes doesn't resolve via NSRunningApplication
            let name = resolveProcessName(pid)
            appName = name
            if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               name.lowercased().contains("chrome") {
                bundleID = bid
            } else {
                bundleID = resolveBundleID(pid)
            }
        }
        let windowInfo = try getFrontmostWindow(pid: pid)
        let windowTitle = windowInfo.title

        // 2. Run capture pipelines concurrently: screenshot + AX
        async let pngData = captureScreenshot(windowID: windowInfo.windowID)
        async let axTree = extractAXTree(pid: pid, windowID: windowInfo.windowID)

        let (png, tree) = try await (pngData, axTree)

        // 3. Extract page URL from AX tree (skip chrome-extension:// noise)
        let pageURL = extractPageUrl(tree)

        // 4. Web capture: headless Chrome CDP (only for Chromium browsers with a URL)
        let webData = await WebCapture.capture(pid: pid, bundleID: bundleID, pageURL: pageURL)

        // 4. Build metadata
        let snapshotID = buildSnapshotID(appName: appName)
        let now = ISO8601DateFormatter().string(from: Date())

        let webInfo = WebCaptureInfo(
            pageUrl: pageURL,
            hasDOM: webData?.renderedHtml != nil,
            domSize: webData?.renderedHtml?.count,
            hasStyles: webData?.stylesJson != nil,
            stylesSize: webData?.stylesJson?.count
        )

        let metadata = SnapshotMetadata(
            id: snapshotID,
            timestamp: now,
            app: AppMetadata(
                bundleID: bundleID,
                name: appName,
                windowTitle: windowTitle,
                pid: pid
            ),
            windowBounds: WindowBounds(
                x: Int(windowInfo.frame.origin.x),
                y: Int(windowInfo.frame.origin.y),
                width: Int(windowInfo.frame.width),
                height: Int(windowInfo.frame.height)
            ),
            image: ImageInfo(
                path: "",
                width: Int(windowInfo.frame.width * 2),
                height: Int(windowInfo.frame.height * 2),
                scaleFactor: 2.0,
                format: "png"
            ),
            accessibility: AccessibilityInfo(
                path: "",
                textLength: tree.flattenText().count,
                elementCount: tree.elementCount
            ),
            web: webInfo
        )

        let summary = SnapshotSummary(
            id: snapshotID,
            timestamp: now,
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            textPreview: String(tree.flattenText().prefix(500)),
            textLength: tree.flattenText().count,
            elementCount: tree.elementCount,
            dirPath: ""
        )

        return CaptureResult(
            pngData: png, axTree: tree, metadata: metadata, summary: summary,
            pageUrl: pageURL,
            renderedHtml: webData?.renderedHtml,
            stylesJson: webData?.stylesJson
        )
    }

    // MARK: - ScreenCaptureKit (Visual Layer)

    private func captureScreenshot(windowID: CGWindowID) async throws -> Data {
        // Get shareable content (all on-screen windows)
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        // Find the target window
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        // Configure filter for this specific window
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Configure stream for single-frame capture
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)   // Retina 2x
        config.height = Int(window.frame.height * 2)
        config.scalesToFit = false
        config.capturesAudio = false
        config.showsCursor = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        // Capture a single frame using SCStream with timeout
        return try await withCheckedThrowingContinuation { continuation in
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let frameOutput = SingleFrameOutput(continuation: continuation)

            // Start a timeout — if no frame arrives within 10s, fail
            let timeoutTask = DispatchWorkItem {
                if !frameOutput.didResume {
                    frameOutput.didResume = true
                    stream.stopCapture()
                    continuation.resume(throwing: CaptureError.screenCaptureError(
                        "Timeout: no frame received. Check Screen Recording permission."))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeoutTask)
            frameOutput.timeoutTask = timeoutTask

            do {
                try stream.addStreamOutput(
                    frameOutput,
                    type: .screen,
                    sampleHandlerQueue: DispatchQueue(label: "com.moly.screenshot")
                )
                stream.startCapture()
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: CaptureError.screenCaptureError(error.localizedDescription))
            }
        }
    }

    // MARK: - Accessibility API (Text Layer)

    func axDiagnostic() -> [String: Any] {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        let binPath = Bundle.main.executablePath ?? "unknown"
        let testPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        var axTest = "not tested"
        if testPID > 0 {
            let app = AXUIElementCreateApplication(testPID)
            if let w: AXUIElement = castAttribute(app.attribute(kAXFocusedWindowAttribute)),
               let children = w.attribute(kAXChildrenAttribute) as? [AXUIElement] {
                axTest = "OK: \(children.count) children in focused window"
            } else {
                axTest = "no focused window"
            }
        }
        return ["ax_trusted": trusted, "binary_path": binPath, "target_pid": testPID, "ax_test": axTest]
    }

    /// Extract AX tree. For multi-process apps like Chrome, search across all windows from
    /// the app PID, window owner PID, and child PIDs, preferring the one with the most content.
    private func extractAXTree(pid: pid_t, windowID: CGWindowID) throws -> AXNode {
        var best: AXNode? = nil
        var bestText = 0

        // Collect all candidate PIDs to try
        var pidsToTry: [pid_t] = [pid]

        // Add CGWindow owner PID
        let options: CGWindowListOption = [.optionOnScreenOnly]
        if let winList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for win in winList {
                if let wid = win[kCGWindowNumber as String] as? UInt32, wid == windowID,
                   let oPID = win[kCGWindowOwnerPID as String] as? pid_t, oPID != pid {
                    pidsToTry.append(oPID)
                }
            }
        }

        // Add child PIDs
        let task = Process()
        task.launchPath = "/bin/ps"; task.arguments = ["-eo", "pid,ppid", "-x"]
        let pipe = Pipe(); task.standardOutput = pipe
        try? task.run(); task.waitUntilExit()
        if let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            for line in out.components(separatedBy: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count == 2, let ch = pid_t(parts[0]), let pr = pid_t(parts[1]), pr == pid, ch != pid {
                    pidsToTry.append(ch)
                }
            }
        }

        // Try each PID, take the window tree with most text content
        for p in pidsToTry {
            let app = AXUIElementCreateApplication(p)
            let windows: [AXUIElement] = (app.attribute(kAXWindowsAttribute) as? [AXUIElement])
                ?? { if let f: AXUIElement = castAttribute(app.attribute(kAXFocusedWindowAttribute)) { return [f] }; return [] }()
            for w in windows {
                let node = traverse(element: w, depth: 0, maxDepth: 50, maxChildren: 800)
                let textLen = countText(node)
                if textLen > bestText {
                    best = node
                    bestText = textLen
                }
            }
        }

        // Also try system-wide focused element
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if let focused = focusedRef as! AXUIElement? {
            let node = traverse(element: focused, depth: 0, maxDepth: 50, maxChildren: 800)
            let textLen = countText(node)
            if textLen > bestText && textLen > 500 {
                best = node
                bestText = textLen
            }
        }

        print("[AX] Best: \(bestText) chars across \(pidsToTry.count) PIDs")
        return best ?? traverse(element: AXUIElementCreateApplication(pid), depth: 0, maxDepth: 50, maxChildren: 800)
    }

    private func countText(_ node: AXNode) -> Int {
        var total = (node.value?.count ?? 0) + (node.title?.count ?? 0) + (node.desc?.count ?? 0)
        for child in node.children { total += countText(child) }
        return total
    }

    private func traverse(element: AXUIElement, depth: Int, maxDepth: Int, maxChildren: Int) -> AXNode {
        guard depth < maxDepth else {
            return AXNode(role: "truncated", children: [])
        }

        // Extract string attributes safely
        let role = stringAttribute(element.attribute(kAXRoleAttribute)) ?? "unknown"
        let title = stringAttribute(element.attribute(kAXTitleAttribute))
        let value = stringAttribute(element.attribute(kAXValueAttribute))
        let description = stringAttribute(element.attribute(kAXDescriptionAttribute))

        // Extract position (AXValue → CGPoint)
        var position: AXPosition? = nil
        if let posRef = element.attribute(kAXPositionAttribute) {
            var point = CGPoint.zero
            if CFGetTypeID(posRef) == AXValueGetTypeID(),
               AXValueGetValue(posRef as! AXValue, .cgPoint, &point) {
                position = AXPosition(x: Double(point.x), y: Double(point.y))
            }
        }

        // Extract size (AXValue → CGSize)
        var size: AXSize? = nil
        if let sizeRef = element.attribute(kAXSizeAttribute) {
            var sz = CGSize.zero
            if CFGetTypeID(sizeRef) == AXValueGetTypeID(),
               AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz) {
                size = AXSize(width: Double(sz.width), height: Double(sz.height))
            }
        }

        // Extract children
        var children: [AXNode] = []
        if let rawChildren = element.attribute(kAXChildrenAttribute) as? [AXUIElement] {
            for child in rawChildren.prefix(maxChildren) {
                children.append(traverse(element: child, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren))
            }
        }

        return AXNode(
            role: role,
            title: title,
            value: value,
            desc: description,
            position: position,
            size: size,
            children: children
        )
    }

    /// Safely cast a CFTypeRef to AXUIElement.
    private func castAttribute(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref = ref else { return nil }
        return (ref as! AXUIElement)
    }

    /// Safely extract a String from a CFTypeRef.
    private func stringAttribute(_ ref: CFTypeRef?) -> String? {
        guard let ref = ref else { return nil }
        return ref as? String
    }

    /// Extract the page URL from the AX tree by scanning for an AXTextField containing a web address.
    /// Handles both "https://github.com/foo" and bare "github.com" values from Chrome's address bar.
    private func extractPageUrl(_ node: AXNode) -> String? {
        if node.role == "AXTextField", let value = node.value {
            // Try full URL first (https://...)
            if let urlRange = value.range(of: "https?://[^\\s]+", options: .regularExpression) {
                let url = String(value[urlRange])
                if !url.hasPrefix("chrome-extension://") && !url.hasPrefix("chrome://") {
                    return url
                }
            }
            // Try bare domain (e.g. "github.com" in Chrome address bar)
            if let bareRange = value.range(of: "[a-zA-Z0-9][-a-zA-Z0-9]*\\.[a-zA-Z]{2,}[^\\s]*", options: .regularExpression) {
                let bare = String(value[bareRange])
                if bare.contains(".") && !bare.hasPrefix("/") {
                    return "https://\(bare)"
                }
            }
        }
        for child in node.children {
            if let url = extractPageUrl(child) { return url }
        }
        return nil
    }

    /// Resolve human-readable app name from PID when NSRunningApplication fails.
    private func resolveProcessName(_ pid: pid_t) -> String {
        // Try ps command first
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", "\(pid)", "-o", "comm="]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        if let name = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            // "Google Chrome" → "Google Chrome", "Safari" → "Safari"
            if name == "Google Chrome" || name == "Safari" || name == "Firefox" {
                return name
            }
            return name
        }
        // Last resort: CGWindow owner name
        let opts: CGWindowListOption = [.optionOnScreenOnly]
        if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
            for w in list {
                if let oPID = w[kCGWindowOwnerPID as String] as? pid_t, oPID == pid,
                   let owner = w[kCGWindowOwnerName as String] as? String {
                    return owner
                }
            }
        }
        return "Unknown"
    }

    private func resolveBundleID(_ pid: pid_t) -> String {
        // Try mdfind for the process path
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-p", "\(pid)", "-Fn"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if out.contains("Google Chrome") || out.contains("Chrome.app") { return "com.google.Chrome" }
        if out.contains("Safari.app") { return "com.apple.Safari" }
        return "unknown"
    }

    // MARK: - Window Query

    private struct WindowInfo {
        let windowID: CGWindowID
        let title: String
        let frame: CGRect
        let ownerPID: pid_t       // actual window owner (renderer for Chrome)
    }

    private func getFrontmostWindow(pid: pid_t) throws -> WindowInfo {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureError.noVisibleWindow
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else { continue }

            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  w > 50, h > 50 else { continue }

            if let layer = window[kCGWindowLayer as String] as? Int32, layer > 1000 { continue }

            let windowID = CGWindowID(window[kCGWindowNumber as String] as? UInt32 ?? 0)
            let title = window[kCGWindowName as String] as? String ?? ""

            return WindowInfo(
                windowID: windowID,
                title: title,
                frame: CGRect(x: x, y: y, width: w, height: h),
                ownerPID: ownerPID
            )
        }

        throw CaptureError.noVisibleWindow
    }
}

// MARK: - Single-Frame Stream Output

private final class SingleFrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let continuation: CheckedContinuation<Data, Error>
    var didResume = false
    var timeoutTask: DispatchWorkItem?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !didResume, type == .screen,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        didResume = true
        timeoutTask?.cancel()

        // Convert CVPixelBuffer → CGImage → PNG Data
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            continuation.resume(throwing: CaptureError.screenCaptureError("Failed to create CGImage"))
            return
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            continuation.resume(throwing: CaptureError.screenCaptureError("Failed to encode PNG"))
            return
        }

        stream.stopCapture()
        continuation.resume(returning: pngData)
    }
}

// MARK: - Error

enum CaptureError: Error, LocalizedError {
    case noActiveApp
    case noVisibleWindow
    case windowNotFound
    case screenCaptureError(String)
    case accessibilityError(String)

    var errorDescription: String? {
        switch self {
        case .noActiveApp: "No active application found"
        case .noVisibleWindow: "No visible window for frontmost application"
        case .windowNotFound: "Target window not found in shareable content"
        case .screenCaptureError(let msg): "ScreenCaptureKit error: \(msg)"
        case .accessibilityError(let msg): "Accessibility API error: \(msg)"
        }
    }
}

// MARK: - AXUIElement Extension

extension AXUIElement {
    func attribute(_ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attr as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
}
