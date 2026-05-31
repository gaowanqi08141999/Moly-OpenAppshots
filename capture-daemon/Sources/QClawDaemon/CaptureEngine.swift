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
        let frontApp = NSRunningApplication(processIdentifier: pid)
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier ?? "unknown"
        let windowInfo = try getFrontmostWindow(pid: pid)
        let windowTitle = windowInfo.title

        // 2. Run both capture pipelines concurrently
        async let pngData = captureScreenshot(windowID: windowInfo.windowID)
        async let axTree = extractAXTree(pid: pid)

        let (png, tree) = try await (pngData, axTree)

        // 3. Build metadata
        let snapshotID = buildSnapshotID(appName: appName)
        let now = ISO8601DateFormatter().string(from: Date())

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
            )
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

        return CaptureResult(pngData: png, axTree: tree, metadata: metadata, summary: summary)
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
                    sampleHandlerQueue: DispatchQueue(label: "com.qclaw.screenshot")
                )
                stream.startCapture()
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: CaptureError.screenCaptureError(error.localizedDescription))
            }
        }
    }

    // MARK: - Accessibility API (Text Layer)

    /// Diagnostic: check AX permission status for this process.
    func axDiagnostic() -> [String: Any] {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        let binPath = Bundle.main.executablePath ?? "unknown"

        // Try a basic AX call
        let testPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        var axTest = "not tested"
        if testPID > 0 {
            let app = AXUIElementCreateApplication(testPID)
            if let window = app.attribute(kAXFocusedWindowAttribute) {
                let windowElem = window as! AXUIElement
                if let children = windowElem.attribute(kAXChildrenAttribute) as? [AXUIElement] {
                    axTest = "OK: \(children.count) children in focused window"
                } else {
                    axTest = "window found but no children array"
                }
            } else {
                axTest = "no focused window (kAXFocusedWindowAttribute returned nil)"
            }
        }

        return [
            "ax_trusted": trusted,
            "binary_path": binPath,
            "target_pid": testPID,
            "ax_test": axTest
        ]
    }

    private func extractAXTree(pid: pid_t) throws -> AXNode {
        let app = AXUIElementCreateApplication(pid)

        // Focus on the main window first; fall back to focused window or app itself
        let window: AXUIElement? = castAttribute(app.attribute(kAXMainWindowAttribute))
            ?? castAttribute(app.attribute(kAXFocusedWindowAttribute))

        if let w = window {
            return traverse(element: w, depth: 0, maxDepth: 50, maxChildren: 800)
        }
        return traverse(element: app, depth: 0, maxDepth: 50, maxChildren: 800)
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
        // AXUIElement is toll-free bridged with CFType
        return (ref as! AXUIElement)
    }

    /// Safely extract a String from a CFTypeRef.
    private func stringAttribute(_ ref: CFTypeRef?) -> String? {
        guard let ref = ref else { return nil }
        return ref as? String
    }

    // MARK: - Window Query

    private struct WindowInfo {
        let windowID: CGWindowID
        let title: String
        let frame: CGRect
    }

    private func getFrontmostWindow(pid: pid_t) throws -> WindowInfo {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            throw CaptureError.noVisibleWindow
        }

        // Get the frontmost window belonging to the target app.
        // Windows are ordered front-to-back, so the first match is the frontmost.
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else { continue }

            // Skip off-screen or tiny windows
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let w = bounds["Width"] as? CGFloat,
                  let h = bounds["Height"] as? CGFloat,
                  w > 50, h > 50 else { continue }

            // Skip menu bar / system UI layers
            if let layer = window[kCGWindowLayer as String] as? Int32, layer > 1000 {
                continue
            }

            let windowID = CGWindowID(window[kCGWindowNumber as String] as? UInt32 ?? 0)
            let title = window[kCGWindowName as String] as? String ?? ""

            return WindowInfo(
                windowID: windowID,
                title: title,
                frame: CGRect(x: x, y: y, width: w, height: h)
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
