import XCTest
@testable import SymTuneMCP
import SymTuneCore

final class MCPServerRunTests: XCTestCase {

    private func makeServer(transport: MCPTransportProtocol) -> MCPServer {
        MCPServer(transport: transport)
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - run() loop

    func testRunInitializeReturnsResponse() throws {
        let transport = FakeMCPTransport()
        transport.messages = [try jsonData(["jsonrpc": "2.0", "id": 1, "method": "initialize"])]
        let server = makeServer(transport: transport)
        try server.run()
        XCTAssertEqual(transport.sent.count, 1)
        let response = transport.sent[0]
        XCTAssertEqual(response["id"] as? Int, 1)
        XCTAssertNotNil(response["result"])
    }

    func testRunPingReturnsEmptyResult() throws {
        let transport = FakeMCPTransport()
        transport.messages = [try jsonData(["jsonrpc": "2.0", "id": 2, "method": "ping"])]
        let server = makeServer(transport: transport)
        try server.run()
        XCTAssertEqual(transport.sent.count, 1)
        let response = transport.sent[0]
        XCTAssertEqual(response["id"] as? Int, 2)
        XCTAssertNotNil(response["result"])
    }

    func testRunNotificationIsIgnored() throws {
        let transport = FakeMCPTransport()
        transport.messages = [try jsonData(["jsonrpc": "2.0", "method": "notifications/initialized"])]
        let server = makeServer(transport: transport)
        try server.run()
        XCTAssertEqual(transport.sent.count, 0)
    }

    func testRunUnknownMethodReturnsInvalidParamsError() throws {
        let transport = FakeMCPTransport()
        transport.messages = [try jsonData(["jsonrpc": "2.0", "id": 3, "method": "unknown/method"])]
        let server = makeServer(transport: transport)
        try server.run()
        XCTAssertEqual(transport.sent.count, 1)
        let response = transport.sent[0]
        XCTAssertEqual(response["id"] as? Int, 3)
        let error = response["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32602)
    }

    func testRunUnsupportedToolReturnsMethodNotFoundError() throws {
        let transport = FakeMCPTransport()
        transport.messages = [try jsonData([
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": [
                "name": "nonexistent_tool",
                "arguments": ["fraction": 0.5]
            ]
        ])]
        let server = makeServer(transport: transport)
        try server.run()
        XCTAssertEqual(transport.sent.count, 1)
        let response = transport.sent[0]
        XCTAssertEqual(response["id"] as? Int, 4)
        let error = response["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
        let data = error?["data"] as? [String: Any]
        XCTAssertNotNil(data?["exitCode"])
    }

    func testRunNonTuneErrorCaughtAsInternalError() throws {
        let transport = FakeMCPTransport(failSendOnIndices: [0])
        transport.messages = [try jsonData(["jsonrpc": "2.0", "id": 5, "method": "ping"])]
        let server = makeServer(transport: transport)
        try server.run()
        XCTAssertEqual(transport.sent.count, 1)
        let response = transport.sent[0]
        XCTAssertEqual(response["id"] as? Int, 5)
        let error = response["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32603)
    }

    // MARK: - jsonRPCCode mapping

    func testJsonRPCCodeMapping() {
        let server = MCPServer()
        XCTAssertEqual(server.jsonRPCCode(for: .usage("x")), -32602)
        XCTAssertEqual(server.jsonRPCCode(for: .unsupported("x")), -32601)
        XCTAssertEqual(server.jsonRPCCode(for: .notImplemented("x")), -32601)
        XCTAssertEqual(server.jsonRPCCode(for: .config("x")), -32603)
        XCTAssertEqual(server.jsonRPCCode(for: .permission("x")), -32603)
        XCTAssertEqual(server.jsonRPCCode(for: .failed("x")), -32603)
    }
}

// MARK: - Fake transport

final class FakeMCPTransport: MCPTransportProtocol {
    var messages: [Data] = []
    var sent: [[String: Any]] = []
    private var sendAttempts = 0
    private var failSendOnIndices: Set<Int> = []

    init(failSendOnIndices: [Int] = []) {
        self.failSendOnIndices = Set(failSendOnIndices)
    }

    func readMessage() throws -> Data? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }

    func send(_ payload: [String: Any]) throws {
        let index = sendAttempts
        sendAttempts += 1
        if failSendOnIndices.contains(index) {
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        sent.append(payload)
    }
}
