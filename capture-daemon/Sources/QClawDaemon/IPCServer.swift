import Foundation
import ImageIO

/// Lightweight HTTP server over TCP (localhost).
/// Zero external dependencies — uses POSIX sockets + manual HTTP/1.1 parsing.
///
/// Endpoints:
///   POST   /capture           Trigger a capture
///   GET    /snapshots          List snapshots
///   GET    /snapshots/:id      Get full snapshot (JSON)
///   GET    /screenshots/:id    Get screenshot PNG
///   DELETE /snapshots/:id      Delete a snapshot
///   GET    /health             Health check
final class IPCServer {

    private let port: UInt16
    private let engine: CaptureEngine
    private let storage: StorageEngine
    private var listenerSocket: Int32 = -1
    private var isRunning = true

    init(port: UInt16 = 19876, engine: CaptureEngine, storage: StorageEngine) {
        self.port = port
        self.engine = engine
        self.storage = storage
    }

    func start() throws {
        // Create TCP socket
        listenerSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard listenerSocket >= 0 else {
            throw IPCServerError.socketCreationFailed(String(cString: strerror(errno)))
        }

        // Allow address reuse (prevents "Address already in use" on restart)
        var reuse: Int32 = 1
        setsockopt(listenerSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 127.0.0.1:<port>
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(port)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafePointer(to: &addr, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(listenerSocket, saPtr, addrLen)
            }
        }) >= 0 else {
            throw IPCServerError.bindFailed(String(cString: strerror(errno)))
        }

        guard listen(listenerSocket, 10) >= 0 else {
            throw IPCServerError.listenFailed(String(cString: strerror(errno)))
        }

        print("[IPCServer] ✅ Listening on http://127.0.0.1:\(port)")

        // Accept loop
        while isRunning {
            let client = accept(listenerSocket, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                print("[IPCServer] Accept error: \(String(cString: strerror(errno)))")
                break
            }
            DispatchQueue.global().async { [self] in
                handleConnection(client)
            }
        }
    }

    func stop() {
        isRunning = false
        close(listenerSocket)
    }

    // MARK: - Connection Handling

    private func handleConnection(_ client: Int32) {
        defer { close(client) }

        guard let request = readHTTPRequest(client) else { return }

        let (statusCode, contentType, body) = route(
            method: request.method,
            path: request.path,
            query: request.query
        )

        let response = """
            HTTP/1.1 \(statusCode) \(statusText(statusCode))\r
            Content-Type: \(contentType)\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
        _ = response.withCString { ptr in
            Darwin.send(client, ptr, response.utf8.count, 0)
        }
    }

    // MARK: - Routing

    private func route(
        method: String,
        path: String,
        query: [String: String]
    ) -> (Int, String, String) {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)

        switch (method, components.first) {
        case ("GET", "health"):
            let body = #"{"status":"ok"}"#
            return (200, "application/json", body)

        case ("GET", "axdiag"):
            let diag = engine.axDiagnostic()
            if let data = try? JSONSerialization.data(withJSONObject: diag, options: []),
               let json = String(data: data, encoding: .utf8) {
                return (200, "application/json", json)
            }
            return (500, "application/json", #"{"error":"encode failed"}"#)

        case ("POST", "capture"):
            return handleCapture(query: query)

        case ("GET", "snapshots"):
            if components.count == 1 {
                return handleList(query: query)
            } else if components.count == 2 {
                return handleGetSnapshot(id: String(components[1]))
            }

        case ("DELETE", "snapshots"):
            if components.count == 2 {
                return handleDeleteSnapshot(id: String(components[1]))
            }

        case ("GET", "screenshots"):
            if components.count == 2 {
                return handleGetScreenshot(id: String(components[1]), query: query)
            }

        default:
            break
        }

        return (404, "application/json", #"{"error":"not found"}"#)
    }

    // MARK: - Handler Implementations

    private func handleCapture(query: [String: String]) -> (Int, String, String) {
        let sem = DispatchSemaphore(value: 0)
        var output: (Int, String, String)?

        // Support capturing a specific app by PID (used by hotkey to avoid focus-stealing)
        let targetPID: pid_t? = query["pid"].flatMap { pid_t($0) }

        Task {
            do {
                let captureResult: CaptureResult
                if let pid = targetPID {
                    engine.registerAXObserver(for: pid)
                    captureResult = try await engine.captureApp(pid: pid)
                } else {
                    captureResult = try await engine.captureFrontmost()
                }
                let summary = try storage.save(captureResult)
                if let data = try? JSONEncoder().encode(summary),
                   let json = String(data: data, encoding: .utf8) {
                    output = (200, "application/json", json)
                } else {
                    output = (500, "application/json", #"{"error":"encode failed"}"#)
                }
            } catch {
                output = (500, "application/json", #"{"error":"\#(error.localizedDescription)"}"#)
            }
            sem.signal()
        }
        sem.wait()

        return output ?? (500, "application/json", #"{"error":"unknown"}"#)
    }

    private func handleList(query: [String: String]) -> (Int, String, String) {
        do {
            let list = try storage.list(
                appName: query["app"],
                dateFrom: query["from"],
                dateTo: query["to"],
                limit: Int(query["limit"] ?? "20") ?? 20,
                offset: Int(query["offset"] ?? "0") ?? 0
            )
            if let data = try? JSONEncoder().encode(list),
               let json = String(data: data, encoding: .utf8) {
                return (200, "application/json", json)
            }
        } catch {
            print("[IPCServer] list error: \(error)")
        }
        return (500, "application/json", #"{"error":"query failed"}"#)
    }

    private func handleGetSnapshot(id: String) -> (Int, String, String) {
        do {
            guard let full = try storage.getFull(id: id) else {
                return (404, "application/json", #"{"error":"snapshot not found"}"#)
            }
            if let data = try? JSONEncoder().encode(full),
               let json = String(data: data, encoding: .utf8) {
                return (200, "application/json", json)
            }
        } catch {
            print("[IPCServer] getSnapshot error: \(error)")
        }
        return (500, "application/json", #"{"error":"read failed"}"#)
    }

    private func handleGetScreenshot(id: String, query: [String: String]) -> (Int, String, String) {
        do {
            guard var pngData = try storage.getScreenshot(id: id) else {
                return (404, "application/json", #"{"error":"not found"}"#)
            }
            // Resize if max_width specified (token optimization)
            if let maxWidthStr = query["max_width"],
               let maxWidth = Int(maxWidthStr), maxWidth > 0, maxWidth < 4096 {
                if let resized = resizeImage(pngData, maxWidth: maxWidth) {
                    pngData = resized
                    print("[IPCServer] Screenshot resized to maxWidth=\(maxWidth)")
                } else {
                    print("[IPCServer] ⚠️ Resize failed for maxWidth=\(maxWidth), using original")
                }
            }
            let b64 = pngData.base64EncodedString()
            return (200, "application/json", #"{"image_base64":"\#(b64)"}"#)
        } catch {
            return (500, "application/json", #"{"error":"read failed"}"#)
        }
    }

    /// Resize PNG data to a maximum width using CoreGraphics, maintaining aspect ratio.
    private func resizeImage(_ pngData: Data, maxWidth: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else {
            print("[IPCServer] resizeImage: CGImageSourceCreateWithData failed")
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            print("[IPCServer] resizeImage: CGImageSourceCreateImageAtIndex failed")
            return nil
        }
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let scale = min(1.0, CGFloat(maxWidth) / srcW)
        let dstW = Int(srcW * scale)
        let dstH = Int(srcH * scale)
        print("[IPCServer] resizeImage: \(cgImage.width)x\(cgImage.height) → \(dstW)x\(dstH)")
        let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: dstW, height: dstH,
            bitsPerComponent: 8, bytesPerRow: dstW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            print("[IPCServer] resizeImage: CGContext init failed")
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let resized = ctx.makeImage() else {
            print("[IPCServer] resizeImage: ctx.makeImage failed")
            return nil
        }
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData, "public.png" as CFString, 1, nil) else {
            print("[IPCServer] resizeImage: CGImageDestinationCreateWithData failed")
            return nil
        }
        CGImageDestinationAddImage(dest, resized, nil)
        guard CGImageDestinationFinalize(dest) else {
            print("[IPCServer] resizeImage: finalize failed")
            return nil
        }
        print("[IPCServer] resizeImage: success, \(outData.length) bytes")
        return outData as Data
    }

    private func handleDeleteSnapshot(id: String) -> (Int, String, String) {
        do {
            let ok = try storage.delete(id: id)
            return (200, "application/json", #"{"success":\#(ok)}"#)
        } catch {
            return (500, "application/json", #"{"error":"\#(error.localizedDescription)"}"#)
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let query: [String: String]
    }

    private func readHTTPRequest(_ socket: Int32) -> HTTPRequest? {
        var buffer = [UInt8](repeating: 0, count: 16384)
        let n = recv(socket, &buffer, buffer.count, 0)
        guard n > 0 else { return nil }

        let raw = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let fullPath = parts[1]

        let pathParts = fullPath.components(separatedBy: "?")
        let path = pathParts[0]
        var query: [String: String] = [:]

        if pathParts.count > 1 {
            for pair in pathParts[1].components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        return HTTPRequest(method: method, path: path, query: query)
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: "OK"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Unknown"
        }
    }
}

enum IPCServerError: Error, LocalizedError {
    case socketCreationFailed(String)
    case bindFailed(String)
    case listenFailed(String)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let m): "Socket creation failed: \(m)"
        case .bindFailed(let m): "Bind failed: \(m)"
        case .listenFailed(let m): "Listen failed: \(m)"
        }
    }
}
