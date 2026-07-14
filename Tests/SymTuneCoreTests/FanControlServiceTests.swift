import XCTest
@testable import SymTuneCore

final class FanControlServiceTests: XCTestCase {
    #if arch(arm64)
    private func makeAppleSiliconFanKeys(targetRPM: Double = 10, maxRPM: Double = 100, mode: UInt8 = 3) -> [String: FakeSMCKeyResult] {
        let flt = smcEncodeKey("flt ")
        let ui8 = smcEncodeKey("ui8 ")
        return [
            "FNum": FakeSMCKeyResult(dataType: ui8, bytes: [1]),
            "F0Ac": FakeSMCKeyResult(dataType: flt, bytes: floatBytes(targetRPM)),
            "F0Tg": FakeSMCKeyResult(dataType: flt, bytes: floatBytes(targetRPM)),
            "F0Mx": FakeSMCKeyResult(dataType: flt, bytes: floatBytes(maxRPM)),
            "F0Mn": FakeSMCKeyResult(dataType: flt, bytes: floatBytes(5)),
            "F0Md": FakeSMCKeyResult(dataType: ui8, bytes: [mode]),
            "Ftst": FakeSMCKeyResult(dataType: ui8, bytes: [0]),
        ]
    }
    #endif

    #if arch(x86_64)
    private func makeIntelFanKeys(targetRPM: Double = 10, maxRPM: Double = 100, mode: UInt8 = 3) -> [String: FakeSMCKeyResult] {
        let fpe2 = smcEncodeKey("fpe2")
        let ui8 = smcEncodeKey("ui8 ")
        return [
            "FNum": FakeSMCKeyResult(dataType: ui8, bytes: [1]),
            "F0Ac": FakeSMCKeyResult(dataType: fpe2, bytes: fpe2Bytes(targetRPM)),
            "F0Tg": FakeSMCKeyResult(dataType: fpe2, bytes: fpe2Bytes(targetRPM)),
            "F0Mx": FakeSMCKeyResult(dataType: fpe2, bytes: fpe2Bytes(maxRPM)),
            "F0Mn": FakeSMCKeyResult(dataType: fpe2, bytes: fpe2Bytes(5)),
            "F0Md": FakeSMCKeyResult(dataType: ui8, bytes: [mode]),
            "FS!": FakeSMCKeyResult(dataType: smcEncodeKey("ui16"), bytes: [0, 0]),
        ]
    }
    #endif

    private func floatBytes(_ value: Double) -> [UInt8] {
        let raw = Float(value).bitPattern.bigEndian
        return [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF)
        ]
    }

    private func fpe2Bytes(_ value: Double) -> [UInt8] {
        let raw = UInt16((value * 256).rounded())
        return [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
    }

    #if arch(arm64)
    func testAppleSiliconSetFanWritesTargetRPM() throws {
        let conn = FakeSMCConnection(isOpen: true, keys: makeAppleSiliconFanKeys())
        let smc = SMCService(connection: conn)
        let service = FanControlService(smc: smc, sensors: SensorService(smc: smc))

        try service.applyFan(fraction: 0.5, config: TuneConfig())

        let target = conn.writtenKeys.first { $0.key == "F0Tg" }
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.dataType, smcEncodeKey("flt "))
        XCTAssertEqual(target?.bytes, floatBytes(50))
    }

    func testAppleSiliconRestoreAutoClearsFtstAndMode() throws {
        let conn = FakeSMCConnection(isOpen: true, keys: makeAppleSiliconFanKeys())
        let smc = SMCService(connection: conn)
        let service = FanControlService(smc: smc, sensors: SensorService(smc: smc))

        try service.applyFan(fraction: 0.5, config: TuneConfig())
        try service.restoreAuto()

        let mode = conn.writtenKeys.first { $0.key == "F0Md" && $0.bytes == [3] }
        XCTAssertNotNil(mode)
        let ftst = conn.writtenKeys.last { $0.key == "Ftst" }
        XCTAssertEqual(ftst?.bytes, [0])
    }
    #endif

    #if arch(x86_64)
    func testIntelSetFanWritesTargetRPM() throws {
        let conn = FakeSMCConnection(isOpen: true, keys: makeIntelFanKeys())
        let smc = SMCService(connection: conn)
        let service = FanControlService(smc: smc, sensors: SensorService(smc: smc))

        try service.applyFan(fraction: 0.5, config: TuneConfig())

        let target = conn.writtenKeys.first { $0.key == "F0Tg" }
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.dataType, smcEncodeKey("fpe2"))
        XCTAssertEqual(target?.bytes, fpe2Bytes(50))
    }

    func testIntelRestoreAutoWritesOriginalFSBitmask() throws {
        let conn = FakeSMCConnection(isOpen: true, keys: makeIntelFanKeys())
        let smc = SMCService(connection: conn)
        let service = FanControlService(smc: smc, sensors: SensorService(smc: smc))

        try service.applyFan(fraction: 0.5, config: TuneConfig())
        try service.restoreAuto()

        let fs = conn.writtenKeys.last { $0.key == "FS!" }
        XCTAssertEqual(fs?.bytes, [0, 0])
    }
    #endif

    func testFanControlRefusesWhenSMCUnavailable() {
        let conn = FakeSMCConnection(isOpen: false)
        let smc = SMCService(connection: conn)
        let service = FanControlService(smc: smc, sensors: SensorService(smc: smc))

        XCTAssertThrowsError(try service.applyFan(fraction: 0.5, config: TuneConfig())) { error in
            XCTAssertTrue("\(error)".contains("SMC"))
        }
    }

    #if arch(arm64)
    func testFanControlRefusesThermalEmergency() {
        var keys = makeAppleSiliconFanKeys()
        let flt = smcEncodeKey("flt ")
        keys["Ts0S"] = FakeSMCKeyResult(dataType: flt, bytes: floatBytes(95)) // above 90 threshold
        let conn = FakeSMCConnection(isOpen: true, keys: keys)
        let smc = SMCService(connection: conn)
        let service = FanControlService(smc: smc, sensors: SensorService(smc: smc))

        XCTAssertThrowsError(try service.applyFan(fraction: 0.5, config: TuneConfig())) { error in
            XCTAssertTrue("\(error)".contains("thermal"))
        }
    }
    #endif
}
