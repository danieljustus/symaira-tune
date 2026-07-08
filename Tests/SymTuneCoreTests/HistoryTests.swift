import XCTest
@testable import SymTuneCore

final class HistoryTests: XCTestCase {
    private var tmpDir: URL!
    private var service: HistoryService!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("symtune-history-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        service = HistoryService(dataDir: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testLogAndReadEvents() throws {
        let e1 = HistoryEvent(
            timestamp: Date(),
            action: "brightness.set",
            requestedValue: 0.85,
            clampedValue: 0.85,
            appliedValue: 0.85,
            result: "success"
        )
        let e2 = HistoryEvent(
            timestamp: Date(),
            action: "dim.set",
            requestedValue: 0.05,
            clampedValue: 0.15,
            appliedValue: 0.15,
            result: "success"
        )
        let e3 = HistoryEvent(
            timestamp: Date(),
            action: "fan.set",
            requestedValue: 1.5,
            clampedValue: 1.0,
            appliedValue: nil,
            result: "failed",
            errorReason: "helper connection failed"
        )

        service.logEvent(e1)
        service.logEvent(e2)
        service.logEvent(e3)

        let events = service.readEvents()
        XCTAssertEqual(events.count, 3)

        XCTAssertEqual(events[0].action, "brightness.set")
        XCTAssertEqual(events[0].requestedValue, 0.85)
        XCTAssertEqual(events[0].clampedValue, 0.85)
        XCTAssertEqual(events[0].appliedValue, 0.85)
        XCTAssertEqual(events[0].result, "success")
        XCTAssertNil(events[0].errorReason)

        XCTAssertEqual(events[1].action, "dim.set")
        XCTAssertEqual(events[1].requestedValue, 0.05)
        XCTAssertEqual(events[1].clampedValue, 0.15)
        XCTAssertEqual(events[1].appliedValue, 0.15)
        XCTAssertEqual(events[1].result, "success")

        XCTAssertEqual(events[2].action, "fan.set")
        XCTAssertEqual(events[2].requestedValue, 1.5)
        XCTAssertEqual(events[2].clampedValue, 1.0)
        XCTAssertNil(events[2].appliedValue)
        XCTAssertEqual(events[2].result, "failed")
        XCTAssertEqual(events[2].errorReason, "helper connection failed")
    }

    func testControllerHistoryIntegration() throws {
        // Create a controller with a mock/fake display write service and temp dataDir
        let mockDir = tmpDir.appendingPathComponent("controller-mock-data", isDirectory: true)
        let controller = TuneController(
            config: TuneConfig(dimMin: 0.2, dimMax: 0.8, brightnessMin: 0.2, brightnessMax: 0.8),
            displayWrite: FakeDisplayWriteService(),
            dataDir: mockDir
        )

        // Verify history starts empty
        XCTAssertTrue(controller.getHistory().isEmpty)

        // Perform normal brightness write -> clamped (since 0.9 is above 0.8 config max)
        try controller.applyBuiltinBrightness(0.9)

        var history = controller.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].action, "brightness.set")
        XCTAssertEqual(history[0].requestedValue, 0.9)
        XCTAssertEqual(history[0].clampedValue, 0.8)
        XCTAssertEqual(history[0].appliedValue, 0.8)
        XCTAssertEqual(history[0].result, "success")

        // Perform a failed write path (like fan set, which is unsupported on Pro helper)
        XCTAssertThrowsError(try controller.applyFan(fraction: 0.5))

        history = controller.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[1].action, "fan.set")
        XCTAssertEqual(history[1].requestedValue, 0.5)
        XCTAssertEqual(history[1].clampedValue, 0.5)
        XCTAssertNil(history[1].appliedValue)
        XCTAssertEqual(history[1].result, "failed")
        XCTAssertTrue(history[1].errorReason?.contains("SMC helper") == true)
    }
}

// A simple fake display write service to avoid calling actual display hardware inside unit tests
private final class FakeDisplayWriteService: DisplayWriteServiceProtocol, @unchecked Sendable {
    private var brightness: Float = 0.5

    func getBuiltinBrightness() throws -> Double {
        return Double(brightness)
    }

    func setBuiltinBrightness(_ value: Float) throws {
        brightness = value
    }

    func applyExtendedBrightness(_ value: Double, displayID: CGDirectDisplayID?) throws {
        // no-op
    }

    func applyWarmth(_ warmth: Float) throws {
        // no-op
    }

    func resetWarmth() throws {
        // no-op
    }
}
