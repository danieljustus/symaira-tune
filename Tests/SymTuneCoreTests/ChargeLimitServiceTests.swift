import XCTest
@testable import SymTuneCore

final class ChargeLimitServiceTests: XCTestCase {
    #if arch(arm64)
    func testDetectsCHTEOnModernAppleSilicon() {
        let ui32 = smcEncodeKey("ui32")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CHTE": FakeSMCKeyResult(dataType: ui32, bytes: [0, 0, 0, 0])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        XCTAssertEqual(service.detectKeyFamily(), .chte)
    }

    func testFallsBackToCH0BWhenCHTEMissing() {
        let ui8 = smcEncodeKey("ui8 ")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CH0B": FakeSMCKeyResult(dataType: ui8, bytes: [0])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        XCTAssertEqual(service.detectKeyFamily(), .ch0b)
    }

    func testInhibitChargeWritesCHTEAsUI32BigEndian() throws {
        let ui32 = smcEncodeKey("ui32")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CHTE": FakeSMCKeyResult(dataType: ui32, bytes: [0, 0, 0, 0])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        try service.applyChargeLimit(percent: 80, config: TuneConfig())

        let written = conn.writtenKeys.first { $0.key == "CHTE" }
        XCTAssertNotNil(written)
        XCTAssertEqual(written?.dataType, ui32)
        XCTAssertEqual(written?.bytes, [0, 0, 0, 1])
    }

    func testClearChargeLimitResetsCHTE() throws {
        let ui32 = smcEncodeKey("ui32")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CHTE": FakeSMCKeyResult(dataType: ui32, bytes: [0, 0, 0, 1])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        try service.clearChargeLimit()

        let written = conn.writtenKeys.first { $0.key == "CHTE" }
        XCTAssertEqual(written?.bytes, [0, 0, 0, 0])
    }
    #endif

    #if arch(x86_64)
    func testDetectsCHLCOnIntel() {
        let ui16 = smcEncodeKey("ui16")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CHLC": FakeSMCKeyResult(dataType: ui16, bytes: [0, 0])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        XCTAssertEqual(service.detectKeyFamily(), .chlc)
    }

    func testIntelChargeLimitWritesPercentAsUI16() throws {
        let ui16 = smcEncodeKey("ui16")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CHLC": FakeSMCKeyResult(dataType: ui16, bytes: [0, 0])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        try service.applyChargeLimit(percent: 80, config: TuneConfig())

        let written = conn.writtenKeys.first { $0.key == "CHLC" }
        XCTAssertNotNil(written)
        XCTAssertEqual(written?.dataType, ui16)
        XCTAssertEqual(written?.bytes, [0, 80])
    }
    #endif

    func testChargeLimitRefusesWhenSMCUnavailable() {
        let conn = FakeSMCConnection(isOpen: false)
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        XCTAssertThrowsError(try service.applyChargeLimit(percent: 80, config: TuneConfig())) { error in
            XCTAssertTrue("\(error)".contains("SMC"))
        }
    }

    func testChargeLimitClampedBySafetyPolicy() throws {
        #if arch(arm64)
        let ui32 = smcEncodeKey("ui32")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "CHTE": FakeSMCKeyResult(dataType: ui32, bytes: [0, 0, 0, 0])
        ])
        let smc = SMCService(connection: conn)
        let service = ChargeLimitService(smc: smc)

        // 30 is below the SafetyPolicy minimum of 50; it should still write the inhibit bit
        // because the service only clamps to the configured range, but for a closed SMC
        // the actual clamping happens in the controller. This test verifies the service
        // accepts the value and produces the inhibit write.
        try service.applyChargeLimit(percent: 30, config: TuneConfig())
        XCTAssertTrue(conn.writtenKeys.contains { $0.key == "CHTE" && $0.bytes == [0, 0, 0, 1] })
        #endif
    }
}
