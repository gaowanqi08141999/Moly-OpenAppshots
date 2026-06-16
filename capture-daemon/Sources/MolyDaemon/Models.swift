import Foundation

// MARK: - Accessibility Tree

struct AXNode: Codable {
    let role: String
    var title: String?
    var value: String?
    var desc: String?
    var position: AXPosition?
    var size: AXSize?
    var children: [AXNode] = []

    enum CodingKeys: String, CodingKey {
        case role, title, value, children
        case desc = "description"
        case position, size
    }

    /// Recursively flatten all text content.
    func flattenText() -> String {
        var lines: [String] = []
        collectText(into: &lines)
        return lines.joined(separator: "\n")
    }

    private func collectText(into lines: inout [String]) {
        if let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty, v.count < 5000 {
            lines.append("[\(role)] \(v)")
        }
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            lines.append("[\(role):title] \(t)")
        }
        for child in children {
            child.collectText(into: &lines)
        }
    }

    var elementCount: Int {
        1 + children.reduce(0) { $0 + $1.elementCount }
    }
}

struct AXPosition: Codable {
    let x: Double
    let y: Double
}

struct AXSize: Codable {
    let width: Double
    let height: Double
}

// MARK: - Snapshot Metadata

struct AppMetadata: Codable {
    let bundleID: String
    let name: String
    let windowTitle: String
    let pid: Int32
}

struct WindowBounds: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct ImageInfo: Codable {
    let path: String
    let width: Int
    let height: Int
    let scaleFactor: Double
    let format: String
}

struct AccessibilityInfo: Codable {
    let path: String
    let textLength: Int
    let elementCount: Int
}

struct SnapshotMetadata: Codable {
    let id: String
    let timestamp: String
    let app: AppMetadata
    let windowBounds: WindowBounds
    let image: ImageInfo
    let accessibility: AccessibilityInfo
    let web: WebCaptureInfo?
}

// MARK: - API Response Types

struct SnapshotSummary: Codable {
    let id: String
    let timestamp: String
    let appName: String
    let bundleID: String
    let windowTitle: String
    let textPreview: String
    let textLength: Int
    let elementCount: Int
    let dirPath: String
}

struct SnapshotListResponse: Codable {
    let total: Int
    let items: [SnapshotSummary]
}

struct SnapshotFullResponse: Codable {
    let metadata: SnapshotMetadata
    let imageBase64: String
    let axTree: AXNode
    let fullText: String
}

struct CaptureResult {
    let pngData: Data
    let axTree: AXNode
    let metadata: SnapshotMetadata
    let summary: SnapshotSummary
    let pageUrl: String?
    let renderedHtml: String?
    let stylesJson: String?
}

// MARK: - Web Capture

struct WebCaptureInfo: Codable {
    let pageUrl: String?
    let hasDOM: Bool
    let domSize: Int?
    let hasStyles: Bool
    let stylesSize: Int?
    let flagsMissing: Bool
}

// MARK: - Helpers

func buildSnapshotID(appName: String, date: Date = Date()) -> String {
    let fmt = ISO8601DateFormatter()
    let ts = fmt.string(from: date)
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "/", with: "-")
    let safe = appName.replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "/", with: "-")
    return "\(ts)_\(safe)"
}

func sanitizeFilename(_ name: String) -> String {
    name.replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
}
