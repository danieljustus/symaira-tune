import XCTest
@testable import SymTuneMCP
import SymTuneCore

final class MCPServerToolSchemaTests: XCTestCase {
    private var server: MCPServer!

    override func setUp() {
        super.setUp()
        server = MCPServer()
    }

    private func schema(for toolName: String) -> [String: Any]? {
        guard let result = try? server.dispatch(method: "tools/list", params: [:]),
              let tools = result["tools"] as? [[String: Any]]
        else { return nil }
        guard let tool = tools.first(where: { $0["name"] as? String == toolName }),
              let inputSchema = tool["inputSchema"] as? [String: Any]
        else { return nil }
        return inputSchema
    }

    private func valueBounds(from schema: [String: Any]?) -> (minimum: Double, maximum: Double)? {
        guard let properties = schema?["properties"] as? [String: Any],
              let value = properties["value"] as? [String: Any],
              let minimum = value["minimum"] as? Double,
              let maximum = value["maximum"] as? Double
        else { return nil }
        return (minimum, maximum)
    }

    func testSetBrightnessSchemaBounds() {
        let bounds = valueBounds(from: schema(for: "set_brightness"))
        XCTAssertEqual(bounds?.minimum, 0.0)
        XCTAssertEqual(bounds?.maximum, 1.0)
    }

    func testSetExtendedBrightnessSchemaBounds() {
        let bounds = valueBounds(from: schema(for: "set_extended_brightness"))
        XCTAssertEqual(bounds?.minimum, SafetyPolicy.extendedBrightnessMin)
        XCTAssertEqual(bounds?.maximum, SafetyPolicy.extendedBrightnessMax)
    }

    func testSetDimSchemaBounds() {
        let bounds = valueBounds(from: schema(for: "set_dim"))
        XCTAssertEqual(bounds?.minimum, SafetyPolicy.dimMin)
        XCTAssertEqual(bounds?.maximum, SafetyPolicy.dimMax)
    }

    func testSetWarmthSchemaBounds() {
        let bounds = valueBounds(from: schema(for: "set_warmth"))
        XCTAssertEqual(bounds?.minimum, 0.0)
        XCTAssertEqual(bounds?.maximum, 1.0)
    }

    func testSetFanSchemaBounds() {
        guard let schema = schema(for: "set_fan"),
              let properties = schema["properties"] as? [String: Any],
              let fraction = properties["fraction"] as? [String: Any],
              let minimum = fraction["minimum"] as? Double,
              let maximum = fraction["maximum"] as? Double
        else {
            return XCTFail("Could not read set_fan schema")
        }
        XCTAssertEqual(minimum, SafetyPolicy.fanFractionMin)
        XCTAssertEqual(maximum, SafetyPolicy.fanFractionMax)
    }

    func testSetChargeLimitSchemaBounds() {
        guard let schema = schema(for: "set_charge_limit"),
              let properties = schema["properties"] as? [String: Any],
              let percent = properties["percent"] as? [String: Any],
              let minimum = percent["minimum"] as? Int,
              let maximum = percent["maximum"] as? Int
        else {
            return XCTFail("Could not read set_charge_limit schema")
        }
        XCTAssertEqual(minimum, SafetyPolicy.chargeLimitMin)
        XCTAssertEqual(maximum, SafetyPolicy.chargeLimitMax)
    }
}

// MARK: - MCPTransport bounds

final class MCPTransportBoundsTests: XCTestCase {

    func testRejectsOversizedPayload() throws {
        let pipe = Pipe()
        let header = "Content-Length: 9000000\r\n\r\n"
        pipe.fileHandleForWriting.write(header.data(using: .utf8)!)
        pipe.fileHandleForWriting.closeFile()

        let transport = MCPTransport(input: pipe.fileHandleForReading, output: .nullDevice)
        XCTAssertThrowsError(try transport.readMessage()) { error in
            guard case TuneError.failed(let message) = error else {
                return XCTFail("Expected .failed, got \(error)")
            }
            XCTAssertTrue(message.contains("exceeds maximum allowed"), "Unexpected message: \(message)")
        }
    }

    func testRejectsHeaderWithoutTerminator() throws {
        let pipe = Pipe()
        let longHeader = String(repeating: "X-Header: value\r\n", count: 500)
        pipe.fileHandleForWriting.write(longHeader.data(using: .utf8)!)
        pipe.fileHandleForWriting.closeFile()

        let transport = MCPTransport(input: pipe.fileHandleForReading, output: .nullDevice)
        XCTAssertThrowsError(try transport.readMessage()) { error in
            guard case TuneError.failed(let message) = error else {
                return XCTFail("Expected .failed, got \(error)")
            }
            XCTAssertTrue(message.contains("without terminator"), "Unexpected message: \(message)")
        }
    }

    func testAcceptsPayloadAtLimit() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("symtune-mcp-test-\(UUID().uuidString).txt")
        let bodySize = 1024
        let body = String(repeating: "{", count: bodySize)
        let header = "Content-Length: \(body.count)\r\n\r\n"
        let payload = header + body
        try payload.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let input = try FileHandle(forReadingFrom: tmp)
        let transport = MCPTransport(input: input, output: .nullDevice)
        let data = try transport.readMessage()
        XCTAssertEqual(data?.count, body.count)
    }
}
