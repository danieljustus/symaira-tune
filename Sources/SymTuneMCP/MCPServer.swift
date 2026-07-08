import Foundation
import SymTuneCore

/// Minimal MCP (Model Context Protocol) server over stdio, so AI agents can read
/// the Mac's thermal/power/display state and (later) tune it. Same transport
/// shape as the rest of the Symaira family: JSON-RPC 2.0 with `Content-Length`
/// framing, `initialize` / `tools/list` / `tools/call` / `ping`.
///
/// Zero stdout pollution: everything that is not a protocol frame goes to
/// stderr. The server holds at most one keep-awake assertion for its lifetime.
///
/// Responsibilities of this type are limited to JSON-RPC wiring. Transport is
/// handled by `MCPTransport`, tool schemas/callables by `MCPTool` conformers,
/// and the registry by `MCPToolRegistry`.
public final class MCPServer {
    private let controller: TuneController
    private let transport: MCPTransportProtocol
    private let encoder = JSONEncoder()
    private let registry: MCPToolRegistry
    private var keepAwakeToken: KeepAwakeToken?

    public convenience init(controller: TuneController = TuneController()) {
        self.init(controller: controller, transport: MCPTransport())
    }

    init(controller: TuneController = TuneController(), transport: MCPTransportProtocol) {
        self.controller = controller
        self.transport = transport
        self.registry = MCPToolRegistry(tools: MCPServer.defaultTools)
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    public func run() throws {
        while let message = try transport.readMessage() {
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
                try sendError(id: id, code: jsonRPCCode(for: error), message: error.description, data: ["exitCode": error.exitCode])
            } catch {
                try sendError(id: id, code: -32603, message: error.localizedDescription)
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
            return ["tools": registry.toolSchemas()]
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

    private func callTool(params: [String: Any]) throws -> [String: Any] {
        guard let name = params["name"] as? String else {
            throw TuneError.usage("tools/call requires a tool name.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard let tool = registry.tool(named: name) else {
            throw TuneError.usage("Unknown tool '\(name)'.")
        }

        let payload = try tool.invoke(arguments: arguments, controller: controller, keepAwakeToken: &keepAwakeToken)
        let structured = try encodeToJSONObject(payload)
        return [
            "content": [["type": "text", "text": jsonString(structured)]],
            "isError": false,
        ]
    }

    // MARK: - JSON-RPC response helpers

    private func sendResponse(id: Any?, result: [String: Any]) throws {
        var message: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { message["id"] = id }
        try transport.send(message)
    }

    private func sendError(id: Any?, code: Int, message: String, data: [String: Any]? = nil) throws {
        var errorPayload: [String: Any] = ["code": code, "message": message]
        if let data { errorPayload["data"] = data }
        var payload: [String: Any] = ["jsonrpc": "2.0", "error": errorPayload]
        if let id { payload["id"] = id }
        try transport.send(payload)
    }

    /// Map `TuneError` variants to JSON-RPC 2.0 error codes.
    func jsonRPCCode(for error: TuneError) -> Int {
        switch error {
        case .usage:       return -32602  // invalid params
        case .unsupported, .notImplemented: return -32601  // method not found
        case .config, .permission, .failed: return -32603  // internal error
        }
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

    // MARK: - Tool registry

    private static let defaultTools: [MCPTool] = [
        CapabilitiesTool(),
        SensorsTool(),
        BatteryTool(),
        ListDisplaysTool(),
        KeepAwakeTool(),
        GetBrightnessTool(),
        SetBrightnessTool(),
        SetExtendedBrightnessTool(),
        SetWarmthTool(),
        ResetWarmthTool(),
        SetDimTool(),
        ResetDimTool(),
        RestoreTool(),
        SaveProfileTool(),
        LoadProfileTool(),
        ListProfilesTool(),
        DeleteProfileTool(),
        SetFanTool(),
        SetChargeLimitTool(),
        GetStatusTool(),
        GetHistoryTool(),
    ]
}

/// Type-erasing wrapper so heterogeneous `Encodable` payloads share one encode path.
private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encodeImpl = wrapped.encode(to:) }
    func encode(to encoder: Encoder) throws { try encodeImpl(encoder) }
}
