import XCTest
@testable import SymTuneCore

final class SMCRestoreTrackerTests: XCTestCase {
    #if arch(arm64)
    private func makeAppleSiliconKeys() -> [String: FakeSMCKeyResult] {
        let flt = smcEncodeKey("flt ")
        let ui8 = smcEncodeKey("ui8 ")
        let ui32 = smcEncodeKey("ui32")
        return [
            "FNum": FakeSMCKeyResult(dataType: ui8, bytes: [1]),
            "F0Md": FakeSMCKeyResult(dataType: ui8, bytes: [3]),
            "F0Tg": FakeSMCKeyResult(dataType: flt, bytes: [0x41, 0x20, 0, 0]), // 10.0f BE
            "F0Mx": FakeSMCKeyResult(dataType: flt, bytes: [0x42, 0xC8, 0, 0]), // 100.0f BE
            "Ftst": FakeSMCKeyResult(dataType: ui8, bytes: [0]),
            "CHTE": FakeSMCKeyResult(dataType: ui32, bytes: [0, 0, 0, 0]),
            "CH0B": FakeSMCKeyResult(dataType: ui8, bytes: [0]),
            "CH0C": FakeSMCKeyResult(dataType: ui8, bytes: [0]),
        ]
    }

    func testRestoreFanWritesOriginalModeAndClearsFtst() {
        let conn = FakeSMCConnection(isOpen: true, keys: makeAppleSiliconKeys())
        let smc = SMCService(connection: conn)
        let fan = FanControlService(smc: smc, sensors: SensorService(smc: smc))
        let charge = ChargeLimitService(smc: smc)
        let tracker = SMCRestoreTracker(smc: smc, fanControl: fan, chargeLimit: charge)

        tracker.saveFanOriginal(fanIndex: 0)
        tracker.restoreAll()

        let mode = conn.writtenKeys.first { $0.key == "F0Md" }
        XCTAssertEqual(mode?.bytes, [3])
        let ftst = conn.writtenKeys.last { $0.key == "Ftst" }
        XCTAssertEqual(ftst?.bytes, [0])
    }

    func testRestoreChargeReenablesCharging() {
        let conn = FakeSMCConnection(isOpen: true, keys: makeAppleSiliconKeys())
        let smc = SMCService(connection: conn)
        let fan = FanControlService(smc: smc, sensors: SensorService(smc: smc))
        let charge = ChargeLimitService(smc: smc)
        let tracker = SMCRestoreTracker(smc: smc, fanControl: fan, chargeLimit: charge)

        tracker.saveChargeOriginal()
        tracker.restoreAll()

        let chte = conn.writtenKeys.first { $0.key == "CHTE" }
        XCTAssertEqual(chte?.bytes, [0, 0, 0, 0])
    }
    #endif

    #if arch(x86_64)
    private func makeIntelKeys() -> [String: FakeSMCKeyResult] {
        let fpe2 = smcEncodeKey("fpe2")
        let ui8 = smcEncodeKey("ui8 ")
        let ui16 = smcEncodeKey("ui16")
        return [
            "FNum": FakeSMCKeyResult(dataType: ui8, bytes: [1]),
            "F0Md": FakeSMCKeyResult(dataType: ui8, bytes: [3]),
            "F0Tg": FakeSMCKeyResult(dataType: fpe2, bytes: [0x0A, 0x00]), // 10 RPM
            "F0Mx": FakeSMCKeyResult(dataType: fpe2, bytes: [0x64, 0x00]), // 100 RPM
            "FS!": FakeSMCKeyResult(dataType: ui16, bytes: [0, 0]),
            "CHLC": FakeSMCKeyResult(dataType: ui16, bytes: [0, 0]),
        ]
    }

    func testRestoreIntelFanWritesOriginalFSBitmask() {
        let conn = FakeSMCConnection(isOpen: true, keys: makeIntelKeys())
        let smc = SMCService(connection: conn)
        let fan = FanControlService(smc: smc, sensors: SensorService(smc: smc))
        let charge = ChargeLimitService(smc: smc)
        let tracker = SMCRestoreTracker(smc: smc, fanControl: fan, chargeLimit: charge)

        tracker.saveFanOriginal(fanIndex: 0)
        tracker.restoreAll()

        let fs = conn.writtenKeys.last { $0.key == "FS!" }
        XCTAssertEqual(fs?.bytes, [0, 0])
    }
    #endif
}
