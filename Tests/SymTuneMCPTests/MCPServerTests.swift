import XCTest
@testable import SymTuneMCP
@testable import SymTuneCore

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

// MARK: - MCPTool dispatch (tools/call)

final class MCPServerToolCallTests: XCTestCase {
    private var tmpDir: URL!
    private var server: MCPServer!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("symtune-mcp-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let mockDisplay = MockMCPDisplayWriteService()
        let controller = TuneController(displayWrite: mockDisplay, dataDir: tmpDir)
        server = MCPServer(controller: controller)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func callTool(_ name: String, arguments: [String: Any] = [:]) throws -> [String: Any] {
        try server.dispatch(method: "tools/call", params: ["name": name, "arguments": arguments])
    }

    func testCallToolReturnsContentArray() throws {
        let result = try callTool("get_capabilities")
        XCTAssertNotNil(result["content"])
        XCTAssertNotNil(result["isError"])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = result["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
    }

    func testCallToolMissingNameThrows() {
        XCTAssertThrowsError(try server.dispatch(method: "tools/call", params: [:])) { error in
            guard case TuneError.usage(let msg) = error else {
                return XCTFail("Expected .usage, got \(error)")
            }
            XCTAssertTrue(msg.contains("requires a tool name"))
        }
    }

    func testCallToolUnknownToolThrows() {
        XCTAssertThrowsError(try callTool("nonexistent_tool")) { error in
            guard case TuneError.unsupported(let msg) = error else {
                return XCTFail("Expected .unsupported, got \(error)")
            }
            XCTAssertTrue(msg.contains("Unknown tool"))
        }
    }

    func testCallGetCapabilities() throws {
        let result = try callTool("get_capabilities")
        let content = result["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("symtune"))
    }

    func testCallGetSensors() throws {
        let result = try callTool("get_sensors")
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content?.first?["text"])
    }

    func testCallGetBattery() throws {
        let result = try callTool("get_battery")
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content?.first?["text"])
    }

    func testCallGetStatus() throws {
        let result = try callTool("get_status")
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content?.first?["text"])
        let text = content?.first?["text"] as? String
        XCTAssertTrue(text?.contains("health_score") == true)
    }

    func testCallGetHistory() throws {
        let result = try callTool("get_history")
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content?.first?["text"])
    }

    func testCallListDisplays() throws {
        let result = try callTool("list_displays")
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content?.first?["text"])
    }

    func testCallSetDim() throws {
        let result = try callTool("set_dim", arguments: ["value": 0.5])
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testCallResetDim() throws {
        let result = try callTool("reset_dim")
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testCallRestore() throws {
        let result = try callTool("restore")
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testCallKeepAwakeTool() throws {
        let resultEnable = try callTool("keep_awake", arguments: ["enabled": true, "prevent_display_sleep": true])
        XCTAssertEqual(resultEnable["isError"] as? Bool, false)

        let resultDisable = try callTool("keep_awake", arguments: ["enabled": false])
        XCTAssertEqual(resultDisable["isError"] as? Bool, false)
    }

    func testCallGetBrightnessTool() {
        do {
            let result = try callTool("get_brightness")
            XCTAssertEqual(result["isError"] as? Bool, false)
        } catch {
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("unsupported") || msg.contains("display") || msg.contains("failed"))
        }
    }

    func testCallSetBrightnessTool() {
        do {
            let result = try callTool("set_brightness", arguments: ["value": 0.75])
            XCTAssertEqual(result["isError"] as? Bool, false)
        } catch {
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("unsupported") || msg.contains("display") || msg.contains("failed"))
        }
    }

    func testCallSetExtendedBrightnessTool() {
        do {
            let result = try callTool("set_extended_brightness", arguments: ["value": 1.2])
            XCTAssertEqual(result["isError"] as? Bool, false)
        } catch {
            XCTAssertFalse("\(error)".isEmpty)
        }
    }

    func testCallSetWarmthAndResetWarmthTools() {
        do {
            let resultWarmth = try callTool("set_warmth", arguments: ["value": 0.4])
            XCTAssertEqual(resultWarmth["isError"] as? Bool, false)
        } catch {
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("unsupported") || msg.contains("display") || msg.contains("failed"))
        }

        do {
            let resultReset = try callTool("reset_warmth")
            XCTAssertEqual(resultReset["isError"] as? Bool, false)
        } catch {
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("unsupported") || msg.contains("display") || msg.contains("failed"))
        }
    }

    func testCallProfileTools() throws {
        XCTAssertThrowsError(try callTool("save_profile")) { error in
            guard case TuneError.usage = error else { return XCTFail("Expected .usage, got \(error)") }
        }
        XCTAssertThrowsError(try callTool("load_profile")) { error in
            guard case TuneError.usage = error else { return XCTFail("Expected .usage, got \(error)") }
        }
        XCTAssertThrowsError(try callTool("delete_profile")) { error in
            guard case TuneError.usage = error else { return XCTFail("Expected .usage, got \(error)") }
        }

        let saveResult = try callTool("save_profile", arguments: ["name": "reading_mode"])
        XCTAssertEqual(saveResult["isError"] as? Bool, false)

        let listResult = try callTool("list_profiles")
        XCTAssertEqual(listResult["isError"] as? Bool, false)
        let listContent = listResult["content"] as? [[String: Any]]
        let listText = listContent?.first?["text"] as? String
        XCTAssertTrue(listText?.contains("reading_mode") == true)

        let loadResult = try callTool("load_profile", arguments: ["name": "reading_mode"])
        XCTAssertEqual(loadResult["isError"] as? Bool, false)

        let deleteResult = try callTool("delete_profile", arguments: ["name": "reading_mode"])
        XCTAssertEqual(deleteResult["isError"] as? Bool, false)
    }

    func testCallSetFanRequiresSMCOrRoot() {
        XCTAssertThrowsError(try callTool("set_fan", arguments: ["fraction": 0.5])) { error in
            let message = "\(error)"
            XCTAssertTrue(
                message.contains("SMC") || message.contains("root") || message.contains("permission") || message.contains("unsupported"),
                "unexpected error: \(error)"
            )
        }
    }

    func testCallSetChargeLimitRequiresSMCOrRoot() {
        XCTAssertThrowsError(try callTool("set_charge_limit", arguments: ["percent": 80])) { error in
            let message = "\(error)"
            XCTAssertTrue(
                message.contains("SMC") || message.contains("root") || message.contains("permission") || message.contains("unsupported"),
                "unexpected error: \(error)"
            )
        }
    }

    func testCallSetFanSuccess() throws {
        let connection = MockSMCConnection()
        let smcService = SMCService(connection: connection)
        let batterySource = MockBatterySource()
        let controller = TuneController(
            smcService: smcService,
            batterySource: batterySource
        )
        let customServer = MCPServer(controller: controller)

        let result = try customServer.dispatch(
            method: "tools/call",
            params: ["name": "set_fan", "arguments": ["fraction": 0.5]]
        )
        XCTAssertEqual(result["isError"] as? Bool, false)

        // Verify something was written to SMC connection
        XCTAssertFalse(connection.writtenKeys.isEmpty)
    }

    func testCallSetChargeLimitSuccess() throws {
        let connection = MockSMCConnection()
        let smcService = SMCService(connection: connection)
        let batterySource = MockBatterySource()
        let controller = TuneController(
            smcService: smcService,
            batterySource: batterySource
        )
        let customServer = MCPServer(controller: controller)

        let result = try customServer.dispatch(
            method: "tools/call",
            params: ["name": "set_charge_limit", "arguments": ["percent": 80]]
        )
        XCTAssertEqual(result["isError"] as? Bool, false)

        // Verify something was written to SMC connection
        XCTAssertFalse(connection.writtenKeys.isEmpty)
    }

    func testCallClearChargeLimitSuccess() throws {
        let connection = MockSMCConnection()
        let smcService = SMCService(connection: connection)
        let batterySource = MockBatterySource()
        let controller = TuneController(
            smcService: smcService,
            batterySource: batterySource
        )
        let customServer = MCPServer(controller: controller)

        let result = try customServer.dispatch(
            method: "tools/call",
            params: ["name": "clear_charge_limit", "arguments": [:]]
        )
        XCTAssertEqual(result["isError"] as? Bool, false)

        // Verify something was written to SMC connection
        XCTAssertFalse(connection.writtenKeys.isEmpty)
    }

    func testDispatchInitialize() throws {
        let result = try server.dispatch(method: "initialize", params: [:])
        XCTAssertNotNil(result["protocolVersion"])
        XCTAssertNotNil(result["capabilities"])
        XCTAssertNotNil(result["serverInfo"])
    }

    func testDispatchPing() throws {
        let result = try server.dispatch(method: "ping", params: [:])
        XCTAssertTrue(result.isEmpty)
    }

    func testDispatchUnknownMethodThrows() {
        XCTAssertThrowsError(try server.dispatch(method: "unknown/method", params: [:])) { error in
            guard case TuneError.usage(let msg) = error else {
                return XCTFail("Expected .usage, got \(error)")
            }
            XCTAssertTrue(msg.contains("Method not found"))
        }
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

private final class MockMCPDisplayWriteService: DisplayWriteServiceProtocol, @unchecked Sendable {
    var brightness: Double = 0.8
    func getBuiltinBrightness() throws -> Double { brightness }
    func setBuiltinBrightness(_ value: Float) throws { brightness = Double(value) }
    func applyWarmth(_ warmth: Float) throws {}
    func resetWarmth() throws {}
    func applyExtendedBrightness(_ multiplier: Double, displayID: UInt32?) throws {}
}

private final class MockBatterySource: BatterySource {
    func readProperties() -> BatterySourceResult {
        return .success(BatteryProperties(externalConnected: true))
    }
}

private struct MockSMCWrittenKey {
    let key: String
    let dataType: UInt32
    let bytes: [UInt8]
}

private final class MockSMCConnection: SMCConnectionProtocol, @unchecked Sendable {
    var isOpen: Bool = true
    var keys: [String: (UInt32, [UInt8])] = [:]
    var writtenKeys: [MockSMCWrittenKey] = []

    init() {
        // FNum: 1 fan
        keys["FNum"] = (smcEncodeKey("ui8 "), [1])
        #if arch(arm64)
        // Apple Silicon uses flt for target / min / max RPM
        keys["F0Mx"] = encodeFlt(6000.0)
        keys["F0Mn"] = encodeFlt(1200.0)
        keys["F0Md"] = encodeUi8(1)
        keys["CHTE"] = encodeUi32(0) // non-nil for detection
        keys["CH0B"] = encodeUi8(0) // non-nil for detection
        #else
        // Intel uses fpe2 / ui16
        keys["F0Mx"] = encodeFpe2(6000.0)
        keys["F0Mn"] = encodeFpe2(1200.0)
        keys["FS!"] = encodeUi16(0)
        keys["CHLC"] = encodeUi16(0) // non-nil for detection
        #endif
    }

    func readKeyRaw(_ key: String) -> (dataType: UInt32, bytes: [UInt8])? {
        return keys[key]
    }

    func writeKeyRaw(_ key: String, dataType: UInt32, bytes: [UInt8]) -> Bool {
        writtenKeys.append(MockSMCWrittenKey(key: key, dataType: dataType, bytes: bytes))
        #if arch(arm64)
        if key == "F0Md" {
            keys["F0Md"] = (dataType, bytes)
        }
        #endif
        return true
    }

    private func encodeFlt(_ value: Float) -> (UInt32, [UInt8]) {
        let raw = value.bitPattern
        return (
            smcEncodeKey("flt "),
            [
                UInt8((raw >> 24) & 0xFF),
                UInt8((raw >> 16) & 0xFF),
                UInt8((raw >> 8) & 0xFF),
                UInt8(raw & 0xFF)
            ]
        )
    }

    private func encodeFpe2(_ value: Double) -> (UInt32, [UInt8]) {
        let raw = UInt16((value * 256.0).rounded())
        return (
            smcEncodeKey("fpe2"),
            [
                UInt8((raw >> 8) & 0xFF),
                UInt8(raw & 0xFF)
            ]
        )
    }

    private func encodeUi8(_ value: UInt8) -> (UInt32, [UInt8]) {
        return (smcEncodeKey("ui8 "), [value])
    }

    private func encodeUi16(_ value: UInt16) -> (UInt32, [UInt8]) {
        return (
            smcEncodeKey("ui16"),
            [
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
        )
    }

    private func encodeUi32(_ value: UInt32) -> (UInt32, [UInt8]) {
        return (
            smcEncodeKey("ui32"),
            [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
        )
    }
}
