import Foundation
import UIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Lightweight HTTP server on 127.0.0.1 that exposes Trio data
/// to the PebbleKit JS bridge running in the Rebble companion app.
final class PebbleLocalAPIServer {
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let port: UInt16
    private let dataBridge: PebbleDataBridge
    private let commandManager: PebbleCommandManager

    init(dataBridge: PebbleDataBridge, commandManager: PebbleCommandManager, port: UInt16 = 8080) {
        self.dataBridge = dataBridge
        self.commandManager = commandManager
        self.port = port
    }

    deinit { stop() }

    /// Briefly extends process lifetime so Rebble can finish HTTP while Trio is in the background.
    private static func beginShortBackgroundTask() {
        DispatchQueue.main.async {
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "PebbleLocalHTTP") {}
            guard taskID != .invalid else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 25) {
                DispatchQueue.main.async {
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.runServer()
        }
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    private func runServer() {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            debug(.service, "Pebble: failed to create socket")
            return
        }

        var enable: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(serverSocket, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            debug(.service, "Pebble: failed to bind to port \(port)")
            close(serverSocket)
            return
        }

        guard listen(serverSocket, 5) == 0 else {
            debug(.service, "Pebble: failed to listen")
            close(serverSocket)
            return
        }

        isRunning = true
        debug(.service, "Pebble: API server started on http://127.0.0.1:\(port)")

        while isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverSocket, sa, &clientAddrLen)
                }
            }

            guard clientSocket >= 0 else {
                if isRunning { debug(.service, "Pebble: accept failed") }
                continue
            }

            // Give Trio a short background window so Rebble can complete HTTP while Trio is not foreground.
            Self.beginShortBackgroundTask()

            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.handleRequest(clientSocket)
            }
        }
    }

    private func handleRequest(_ clientSocket: Int32) {
        defer { close(clientSocket) }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let request = String(bytes: buffer[0 ..< bytesRead], encoding: .utf8) ?? ""
        let method = extractMethod(from: request)
        let path = extractPath(from: request)
        let body = extractBody(from: request)

        let (statusCode, contentType, responseBody) = routeRequest(method: method, path: path, body: body)
        let response = buildHTTPResponse(statusCode: statusCode, contentType: contentType, body: responseBody)
        let responseData = [UInt8](response.utf8)
        _ = write(clientSocket, responseData, responseData.count)
    }

    private func routeRequest(method: String, path: String, body: String?) -> (Int, String, String) {
        if method == "GET" {
            switch path {
            case "/":
                return (200, "text/html; charset=utf-8", Self.browserLandingHTML())
            case "/api/cgm": return (200, "application/json", dataBridge.cgmJSON())
            case "/api/loop": return (200, "application/json", dataBridge.loopJSON())
            case "/api/pump": return (200, "application/json", dataBridge.pumpJSON())
            case "/api/all": return (200, "application/json", dataBridge.allDataJSON())
            case "/api/commands/pending": return (200, "application/json", commandManager.pendingCommandsJSON())
            case "/health": return (200, "application/json", "{\"status\":\"ok\"}")
            default: return (404, "application/json", "{\"error\":\"not found\"}")
            }
        }

        if method == "POST" {
            switch path {
            case "/api/bolus": return handleBolusRequest(body)
            case "/api/carbs": return handleCarbRequest(body)
            case "/api/command/confirm": return handleConfirmCommand(body)
            case "/api/command/reject": return handleRejectCommand(body)
            default: return (404, "application/json", "{\"error\":\"not found\"}")
            }
        }

        return (405, "application/json", "{\"error\":\"method not allowed\"}")
    }

    /// Minimal HTML so Safari on the same iPhone can confirm the server and follow links to JSON endpoints.
    private static func browserLandingHTML() -> String {
        """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Trio Pebble API</title></head>
        <body style="font-family: system-ui; padding: 1rem; max-width: 36rem;">
        <h1>Trio Pebble API</h1>
        <p>Local server is running on this iPhone.</p>
        <ul>
        <li><a href="/health"><code>/health</code></a> — JSON status</li>
        <li><a href="/api/cgm"><code>/api/cgm</code></a> — CGM JSON</li>
        <li><a href="/api/loop"><code>/api/loop</code></a> — loop JSON</li>
        <li><a href="/api/pump"><code>/api/pump</code></a> — pump JSON</li>
        <li><a href="/api/all"><code>/api/all</code></a> — combined JSON</li>
        </ul>
        <p style="color:#666;font-size:0.9rem;">Use Safari <em>on this device</em>; another computer’s browser cannot reach <code>127.0.0.1</code> here.</p>
        </body></html>
        """
    }

    private func handleBolusRequest(_ body: String?) -> (Int, String, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let units = json["units"] as? Double
        else { return (400, "application/json", "{\"error\":\"invalid request, requires 'units'\"}") }

        guard let command = commandManager.queueBolus(units: units) else {
            return (400, "application/json", "{\"error\":\"bolus exceeds safety limits\"}")
        }

        return (202, "application/json", "{\"status\":\"pending_confirmation\",\"commandId\":\"\(command.id)\",\"message\":\"Confirm \(String(format: "%.2f", units))U bolus on iPhone\",\"type\":\"bolus\"}")
    }

    private func handleCarbRequest(_ body: String?) -> (Int, String, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let grams = json["grams"] as? Double
        else { return (400, "application/json", "{\"error\":\"invalid request, requires 'grams'\"}") }

        let absorptionHours = json["absorptionHours"] as? Double ?? 3.0

        guard let command = commandManager.queueCarbEntry(grams: grams, absorptionHours: absorptionHours) else {
            return (400, "application/json", "{\"error\":\"carb amount exceeds safety limits\"}")
        }

        return (202, "application/json", "{\"status\":\"pending_confirmation\",\"commandId\":\"\(command.id)\",\"message\":\"Confirm \(String(format: "%.0f", grams))g carbs on iPhone\",\"type\":\"carbEntry\"}")
    }

    private func handleConfirmCommand(_ body: String?) -> (Int, String, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commandId = json["commandId"] as? String
        else { return (400, "application/json", "{\"error\":\"requires 'commandId'\"}") }

        commandManager.confirmCommand(commandId)
        return (200, "application/json", "{\"status\":\"confirmed\"}")
    }

    private func handleRejectCommand(_ body: String?) -> (Int, String, String) {
        guard let body = body,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commandId = json["commandId"] as? String
        else { return (400, "application/json", "{\"error\":\"requires 'commandId'\"}") }

        commandManager.rejectCommand(commandId)
        return (200, "application/json", "{\"status\":\"rejected\"}")
    }

    private func extractMethod(from request: String) -> String {
        request.components(separatedBy: "\r\n").first?.components(separatedBy: " ").first ?? "GET"
    }

    private func extractPath(from request: String) -> String {
        let parts = request.components(separatedBy: "\r\n").first?.components(separatedBy: " ") ?? []
        return parts.count >= 2 ? parts[1] : "/"
    }

    private func extractBody(from request: String) -> String? {
        guard let range = request.range(of: "\r\n\r\n") else { return nil }
        let body = String(request[range.upperBound...])
        return body.isEmpty ? nil : body
    }

    private func buildHTTPResponse(statusCode: Int, contentType: String, body: String) -> String {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 202: statusText = "Accepted"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }
        return "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)"
    }
}
