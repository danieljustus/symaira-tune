import Foundation
import SymTuneCore

/// Minimal MCP (Model Context Protocol) server over stdio, so AI agents can read
/// the Mac's thermal/power/display state and (later) tune it. Same transport
/// shape as the rest of the Symaira family: JSON-RPC 2.0 with `Content-Length`
/// framing, `initialize` / `tools/list` / `tools/call` / `ping`.
///
/// Zero stdout pollution: everything that is not a protocol frame goes to
/// stderr. The server holds at most one keep-awake assertion for its lifetime.
public final class MCPServer {
    private let controller: TuneController
    private let encoder = JSONEncoder()
    private var keepAwakeToken: KeepAwakeToken?

    public init(controller: TuneController = TuneController()) {
        self.controller = controller
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    public func run() throws {
        let stdin = FileHandle.standardInput
        while let message = try readMessage(from: stdin) {
            guard
                let object = try JSONSerialization.jsonObject(with: message) as? [String: Any],
                let method = object["method"] as? String
            else { continue }

            let id = object["id"]
            let params = object["params"] as? [String: Any] ?? [:]

            // Notifications (no id) get no response.
            if id == nil, method.hasPrefix("notifications/") { continue }

            do {
                let result = try dispatch(method: method, params: params)
                try sendResponse(id: id, result: result)
            } catch let error as TuneError {
                try sendError(id: id, code: -32000, message: error.description)
            } catch {
                try sendError(id: id, code: -32000, message: error.localizedDescription)
            }
        }
    }

    func dispatch(method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            return initializeResult(requestedProtocol: params["protocolVersion"] as? String)
        case "notifications/initialized", "ping":
            return [:]
        case "tools/list":
            return ["tools": tools()]
        case "tools/call":
            return try callTool(params: params)
        default:
            throw TuneError.usage("Method not found: \(method)")
        }
    }

    private func initializeResult(requestedProtocol: String?) -> [String: Any] {
        [
            "protocolVersion": requestedProtocol ?? "2024-11-05",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "symtune", "version": TuneVersion.current],
        ]
    }

    private func tools() -> [[String: Any]] {
        let value: [String: Any] = [
            "type": "object",
            "properties": ["value": ["type": "number"]],
            "required": ["value"],
        ]
        return [
            tool("get_capabilities", "Report tool version, host info, and which tuning capabilities are available.", [:]),
            tool("get_sensors", "Read thermal pressure and (when available) temperatures and fan RPM.", [:]),
            tool("get_battery", "Read battery health: charge %, cycle count, capacity, condition.", [:]),
            tool("list_displays", "List displays with EDR headroom (extended-brightness capability).", [:]),
            tool("keep_awake", "Prevent the Mac from idle-sleeping while the server runs.", [
                "type": "object",
                "properties": [
                    "enabled": ["type": "boolean"],
                    "prevent_display_sleep": ["type": "boolean", "default": false],
                ],
                "required": ["enabled"],
            ]),
            tool("set_extended_brightness", "Set extended/EDR brightness multiplier (1.0–1.6). Planned — returns an error in v0.1.", value),
            tool("set_fan", "Set fan speed as a fraction 0.0–1.0. Pro — requires the privileged helper.", [
                "type": "object",
                "properties": ["fraction": ["type": "number"]],
                "required": ["fraction"],
            ]),
            tool("set_charge_limit", "Hold battery charge at a target percent (50–100). Pro — requires the privileged helper.", [
                "type": "object",
                "properties": ["percent": ["type": "integer"]],
                "required": ["percent"],
            ]),
        ]
    }

    private func tool(_ name: String, _ description: String, _ input: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": input.isEmpty ? ["type": "object", "properties": [:]] : input,
        ]
    }

    private func callTool(params: [String: Any]) throws -> [String: Any] {
        guard let name = params["name"] as? String else {
            throw TuneError.usage("tools/call requires a tool name.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        let payload: Encodable
        switch name {
        case "get_capabilities":
            payload = controller.capabilities()
        case "get_sensors":
            payload = controller.sensors_report()
        case "get_battery":
            payload = controller.batteryReport()
        case "list_displays":
            payload = controller.displaysReport()
        case "keep_awake":
            payload = try handleKeepAwake(arguments)
        case "set_extended_brightness":
            try controller.applyExtendedBrightness(requireDouble(arguments["value"], name: "value"))
            payload = ["applied": false] // unreachable; apply throws in v0.1
        case "set_fan":
            try controller.applyFan(fraction: requireDouble(arguments["fraction"], name: "fraction"))
            payload = ["applied": false]
        case "set_charge_limit":
            try controller.applyChargeLimit(percent: requireInt(arguments["percent"], name: "percent"))
            payload = ["applied": false]
        default:
            throw TuneError.usage("Unknown tool '\(name)'.")
        }

        let structured = try encodeToJSONObject(payload)
        return [
            "content": [["type": "text", "text": jsonString(structured)]],
            "structuredContent": structured,
            "isError": false,
        ]
    }

    private struct KeepAwakeState: Encodable {
        let enabled: Bool
        let preventDisplaySleep: Bool
    }

    private func handleKeepAwake(_ arguments: [String: Any]) throws -> Encodable {
        let enabled = arguments["enabled"] as? Bool ?? false
        let preventDisplay = arguments["prevent_display_sleep"] as? Bool ?? false
        if enabled {
            if keepAwakeToken == nil {
                keepAwakeToken = try controller.beginKeepAwake(
                    reason: "symtune MCP keep_awake",
                    preventDisplaySleep: preventDisplay
                )
            }
        } else if let token = keepAwakeToken {
            controller.endKeepAwake(token)
            keepAwakeToken = nil
        }
        return KeepAwakeState(enabled: keepAwakeToken != nil, preventDisplaySleep: preventDisplay)
    }

    // MARK: - Encoding helpers

    private func encodeToJSONObject(_ value: Encodable) throws -> Any {
        let data = try encoder.encode(AnyEncodable(value))
        return try JSONSerialization.jsonObject(with: data)
    }

    private func jsonString(_ object: Any) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private func requireDouble(_ value: Any?, name: String) throws -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String, let double = Double(string) { return double }
        throw TuneError.usage("Missing required numeric argument '\(name)'.")
    }

    private func requireInt(_ value: Any?, name: String) throws -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let int = Int(string) { return int }
        throw TuneError.usage("Missing required integer argument '\(name)'.")
    }

    // MARK: - Transport (Content-Length framed JSON-RPC over stdio)

    private func sendResponse(id: Any?, result: [String: Any]) throws {
        var message: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { message["id"] = id }
        try send(message)
    }

    private func sendError(id: Any?, code: Int, message: String) throws {
        var payload: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { payload["id"] = id }
        try send(payload)
    }

    private func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        if let header = "Content-Length: \(data.count)\r\n\r\n".data(using: .utf8) {
            FileHandle.standardOutput.write(header)
        }
        FileHandle.standardOutput.write(data)
    }

    private func readMessage(from handle: FileHandle) throws -> Data? {
        guard let headerData = try readHeader(from: handle), !headerData.isEmpty else { return nil }
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw TuneError.failed("Failed to decode MCP header.")
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let lengthLine = lines.first(where: { $0.lowercased().hasPrefix("content-length:") }) else {
            throw TuneError.failed("Missing Content-Length header.")
        }
        let value = lengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let length = Int(value) else {
            throw TuneError.failed("Invalid Content-Length header.")
        }
        return try readBytes(from: handle, count: length)
    }

    private func readHeader(from handle: FileHandle) throws -> Data? {
        var data = Data()
        while true {
            guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
                return data.isEmpty ? nil : data
            }
            data.append(chunk)
            if data.count >= 4, data.suffix(4) == Data([13, 10, 13, 10]) { return data }
        }
    }

    private func readBytes(from handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw TuneError.failed("Unexpected end of input while reading MCP payload.")
            }
            data.append(chunk)
        }
        return data
    }
}

/// Type-erasing wrapper so heterogeneous `Encodable` payloads share one encode path.
private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encodeImpl = wrapped.encode(to:) }
    func encode(to encoder: Encoder) throws { try encodeImpl(encoder) }
}
