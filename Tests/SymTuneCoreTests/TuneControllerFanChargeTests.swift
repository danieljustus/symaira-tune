import XCTest
@testable import SymTuneCore

// MARK: - TuneController Fan / Charge-Limit Tests

final class TuneControllerFanChargeTests: XCTestCase {
    private func makeController(
        keys: [String: FakeSMCKeyResult] = [:],
        batteryResult: BatterySourceResult = .unavailable
    ) -> TuneController {
        let smc = SMCService(connection: FakeSMCConnection(isOpen: true, keys: keys))
        let batterySource = FakeBatterySource(result: batteryResult)
        return TuneController(
            config: TuneConfig(),
            displayWrite: MockDisplayWriteService(),
            smcService: smc,
            batterySource: batterySource
        )
    }

    private func fpe2(_ value: Double) -> FakeSMCKeyResult {
        let raw = UInt16((value * 256.0).rounded())
        return FakeSMCKeyResult(dataType: smcEncodeKey("fpe2"), bytes: [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)])
    }

    private func ui8(_ value: UInt8) -> FakeSMCKeyResult {
        FakeSMCKeyResult(dataType: smcEncodeKey("ui8 "), bytes: [value])
    }

    private func ui32(_ value: UInt32) -> FakeSMCKeyResult {
        FakeSMCKeyResult(
            dataType: smcEncodeKey("ui32"),
            bytes: [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
        )
    }

    private func flt(_ value: Double) -> FakeSMCKeyResult {
        let raw = Float(value).bitPattern
        return FakeSMCKeyResult(
            dataType: smcEncodeKey("flt "),
            bytes: [
                UInt8((raw >> 24) & 0xFF),
                UInt8((raw >> 16) & 0xFF),
                UInt8((raw >> 8) & 0xFF),
                UInt8(raw & 0xFF)
            ]
        )
    }

    func testApplyFanSuccess() {
        let controller = makeController(keys: [
            "FNum": ui8(1),
            "F0Md": ui8(3),
            "F0Tg": flt(3000),
            "F0Mx": flt(6000),
            "F0Mn": flt(1200),
            "Tp01": fpe2(30.0)
        ])
        XCTAssertNoThrow(try controller.applyFan(fraction: 0.5))
    }

    func testApplyFanNoFansDetected() {
        let controller = makeController(keys: [
            "FNum": ui8(0),
            "Tp01": fpe2(30.0)
        ])
        XCTAssertThrowsError(try controller.applyFan(fraction: 0.5)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("SMC reports no fans") || message.contains("unsupported"), "unexpected: \(message)")
        }
    }

    func testRestoreFanAuto() {
        let controller = makeController(keys: [
            "FNum": ui8(1),
            "F0Md": ui8(3),
            "F0Tg": flt(3000)
        ])
        XCTAssertNoThrow(try controller.restoreFanAuto())
    }

    func testApplyChargeLimitSuccess() {
        let controller = makeController(
            keys: ["CHTE": ui32(0)],
            batteryResult: .success(BatteryProperties(externalConnected: true))
        )
        XCTAssertNoThrow(try controller.applyChargeLimit(percent: 80))
    }

    func testApplyChargeLimitRequiresACPower() {
        let controller = makeController(
            keys: ["CHTE": ui32(0)],
            batteryResult: .success(BatteryProperties(externalConnected: false))
        )
        XCTAssertThrowsError(try controller.applyChargeLimit(percent: 80)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("AC power"), "unexpected: \(message)")
        }
    }

    func testClearChargeLimit() {
        let controller = makeController(keys: ["CHTE": ui32(0)])
        XCTAssertNoThrow(try controller.clearChargeLimit())
    }

    func testActiveFanFraction() {
        let controller = makeController(keys: [
            "FNum": ui8(1),
            "F0Md": ui8(1),
            "F0Tg": flt(3000),
            "F0Mx": flt(6000)
        ])
        XCTAssertEqual(controller.activeOverrides().fanFraction ?? 0, 0.5, accuracy: 0.01)
    }

    func testActiveChargeLimitPercent() {
        let controller = makeController(keys: ["CHTE": ui32(1)])
        XCTAssertEqual(controller.activeOverrides().chargeLimitPercent, 80)
    }
}

// MARK: - TuneController Error Mapping Tests

final class TuneControllerErrorMappingTests: XCTestCase {
    func testMapFanControlError() {
        XCTAssertEqual(mapFanControlError(.noFansDetected).description, "unsupported: SMC reports no fans; fan control is unavailable")
        XCTAssertEqual(mapFanControlError(.fanModeWriteRejected(0)).description, "permission error: SMC rejected manual mode for fan 0; run with sudo")
        XCTAssertEqual(mapFanControlError(.targetRPMWriteFailed(1)).description, "permission error: SMC rejected target RPM for fan 1")
        XCTAssertEqual(mapFanControlError(.unsupportedPlatform).description, "unsupported: Fan control is not supported on this platform")
    }

    func testMapValidationError() {
        XCTAssertEqual(mapValidationError(.noSMCConnection).description, "permission error: SMC not available for write")
        XCTAssertEqual(mapValidationError(.thermalEmergency(95.0)).description, "permission error: thermal emergency at 95.0°C; refusing write")
        XCTAssertEqual(mapValidationError(.fanMaxRPMUnavailable(0)).description, "unsupported: SMC did not report maximum RPM for fan 0")
        XCTAssertEqual(mapValidationError(.chargeLimitNoACPower).description, "permission error: charge limit requires AC power and SMC write access")
    }
}
