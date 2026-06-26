import Foundation
import SymTuneCore

/// A single MCP tool: schema metadata plus an invocation handler.
/// Concrete tools are immutable structs — safe to share across concurrency domains.
protocol MCPTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: Any] { get }

    /// Invoke the tool with parsed arguments.
    /// - Parameters:
    ///   - arguments: the parsed JSON-RPC `arguments` object.
    ///   - controller: facade to the core services.
    ///   - keepAwakeToken: in-out token shared across the server lifetime for the
    ///     `keep_awake` tool; other tools should leave it untouched.
    func invoke(
        arguments: [String: Any],
        controller: TuneController,
        keepAwakeToken: inout KeepAwakeToken?
    ) throws -> Encodable
}

/// Registry that maps tool names to implementations and renders the `tools/list`
/// schema array. Adding a new tool is a single entry in `MCPServer.defaultTools`.
struct MCPToolRegistry {
    private let tools: [MCPTool]
    private let toolsByName: [String: MCPTool]

    init(tools: [MCPTool]) {
        self.tools = tools
        self.toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    func tool(named name: String) -> MCPTool? {
        toolsByName[name]
    }

    func toolSchemas() -> [[String: Any]] {
        tools.map { schema(for: $0) }
    }
}

private func schema(for tool: MCPTool) -> [String: Any] {
    [
        "name": tool.name,
        "description": tool.description,
        "inputSchema": tool.inputSchema.isEmpty ? ["type": "object", "properties": [:]] : tool.inputSchema,
    ]
}
