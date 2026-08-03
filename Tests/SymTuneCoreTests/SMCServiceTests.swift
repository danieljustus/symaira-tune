import XCTest
@testable import SymTuneCore

final class SMCServiceTests: XCTestCase {
    func testUnavailableConnectionReturnsEmptyTemperatures() {
        let conn = FakeSMCConnection(isOpen: false)
        let service = SMCService(connection: conn)

        XCTAssertFalse(service.isAvailable)
        XCTAssertEqual(service.readTemperatures(), [])
        XCTAssertEqual(service.readFans(), [])
    }

    func testMissingTemperatureKeysReturnsEmpty() {
        let conn = FakeSMCConnection(isOpen: true, keys: [:])
        let service = SMCService(connection: conn)

        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(service.readTemperatures(), [])
    }

    func testTemperatureReadings() {
        let fpe2 = smcEncodeKey("fpe2")
        // 0x0100 / 256 = 1.0
        #if arch(arm64)
        let key = "Tp01"
        let label = "CPU Core 1"
        #else
        let key = "TC0C"
        let label = "CPU Core 1"
        #endif
        let conn = FakeSMCConnection(isOpen: true, keys: [
            key: FakeSMCKeyResult(dataType: fpe2, bytes: [0x01, 0x00])
        ])
        let service = SMCService(connection: conn)

        let readings = service.readTemperatures()
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.key, key)
        XCTAssertEqual(readings.first?.label, label)
        XCTAssertEqual(readings.first?.celsius ?? 0, 1.0, accuracy: 0.01)
    }

    func testFanCountZeroReturnsEmpty() {
        let ui8 = smcEncodeKey("ui8 ")
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "FNum": FakeSMCKeyResult(dataType: ui8, bytes: [0])
        ])
        let service = SMCService(connection: conn)

        XCTAssertEqual(service.readFans(), [])
    }

    func testFanReadings() {
        let ui8 = smcEncodeKey("ui8 ")
        let fpe2 = smcEncodeKey("fpe2")
        // 0x0500 / 256 = 5.0
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "FNum": FakeSMCKeyResult(dataType: ui8, bytes: [1]),
            "F0Ac": FakeSMCKeyResult(dataType: fpe2, bytes: [0x05, 0x00])
        ])
        let service = SMCService(connection: conn)

        let fans = service.readFans()
        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans.first?.index, 0)
        XCTAssertEqual(fans.first?.label, "Main Fan")
        XCTAssertEqual(fans.first?.rpm, 5)
    }

    func testWriteKeyValueEncodesAndDelegates() {
        let conn = FakeSMCConnection(isOpen: true)
        let service = SMCService(connection: conn)

        let success = service.writeKeyValue("F0Tg", value: 2.0, dataType: "fpe2")
        XCTAssertTrue(success)
        XCTAssertEqual(conn.writtenKeys.count, 1)
        let written = conn.writtenKeys.first!
        XCTAssertEqual(written.key, "F0Tg")
        XCTAssertEqual(written.bytes, [0x02, 0x00])
    }

    func testWriteKeyValueEncodesFloatBigEndian() {
        let conn = FakeSMCConnection(isOpen: true)
        let service = SMCService(connection: conn)

        let success = service.writeKeyValue("F0Tg", value: 42.0, dataType: "flt ")
        XCTAssertTrue(success)
        let written = conn.writtenKeys.first!
        XCTAssertEqual(written.key, "F0Tg")
        XCTAssertEqual(written.dataType, smcEncodeKey("flt "))

        let val: Float = 42.0
        let raw = val.bitPattern
        let expected = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF)
        ]
        XCTAssertEqual(written.bytes, expected)
    }

    func testWriteKeyValueEncodesUInt32BigEndian() {
        let conn = FakeSMCConnection(isOpen: true)
        let service = SMCService(connection: conn)

        let success = service.writeKeyValue("CHTE", value: 1, dataType: "ui32")
        XCTAssertTrue(success)
        let written = conn.writtenKeys.first!
        XCTAssertEqual(written.key, "CHTE")
        XCTAssertEqual(written.dataType, smcEncodeKey("ui32"))
        XCTAssertEqual(written.bytes, [0, 0, 0, 1])
    }

    func testWriteKeyValueUnknownTypeReturnsFalse() {
        let conn = FakeSMCConnection(isOpen: true)
        let service = SMCService(connection: conn)

        XCTAssertFalse(service.writeKeyValue("X", value: 1.0, dataType: "abcd"))
        XCTAssertTrue(conn.writtenKeys.isEmpty)
    }

    // MARK: - Open probe

    func testOpenProbeAsksForTheUniversalKeyCountKey() {
        var probedKey: UInt32 = 0
        _ = HardwareSMCConnection.probeIndicatesOpen { input, _ in
            probedKey = input.key
            return false
        }
        XCTAssertEqual(smcDecodeKey(probedKey), "#KEY")
    }

    func testOpenProbeSucceedsWhenTheSMCReportsSuccess() {
        let open = HardwareSMCConnection.probeIndicatesOpen { _, output in
            output.data[40] = 0 // result == kSMCSuccess
            return true
        }
        XCTAssertTrue(open)
    }

    /// The regression from #210: on macOS builds that reject the raw AppleSMC
    /// interface, the transport call succeeds while the firmware answers
    /// kSMCKeyNotFound for every key — including `#KEY`. That is not an open
    /// connection, and reporting it as one makes `smc_supported` lie.
    func testOpenProbeFailsWhenTransportSucceedsButSMCRejectsTheKey() {
        let open = HardwareSMCConnection.probeIndicatesOpen { _, output in
            output.data[40] = 132 // kSMCKeyNotFound
            return true
        }
        XCTAssertFalse(open)
    }

    func testOpenProbeFailsWhenTheTransportCallFails() {
        XCTAssertFalse(HardwareSMCConnection.probeIndicatesOpen { _, _ in false })
    }

    // MARK: - System power (readSystemPower)

    private func fltKey(_ value: Double) -> FakeSMCKeyResult {
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

    func testReadSystemPowerNilWhenConnectionClosed() {
        let service = SMCService(connection: FakeSMCConnection(isOpen: false))
        XCTAssertNil(service.readSystemPower())
    }

    func testReadSystemPowerNilWhenKeysAbsent() {
        let service = SMCService(connection: FakeSMCConnection(isOpen: true, keys: [:]))
        XCTAssertNil(service.readSystemPower())
    }

    func testReadSystemPowerReadsAllThreeKeys() {
        let conn = FakeSMCConnection(isOpen: true, keys: [
            "VD0R": fltKey(20.0),
            "ID0R": fltKey(0.5),
            "PDTR": fltKey(10.0)
        ])
        let service = SMCService(connection: conn)

        let power = service.readSystemPower()
        XCTAssertEqual(power?.volts ?? 0, 20.0, accuracy: 0.0001)
        XCTAssertEqual(power?.amps ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(power?.watts ?? 0, 10.0, accuracy: 0.0001)
        // Read-only: a power read must never write to the SMC.
        XCTAssertTrue(conn.writtenKeys.isEmpty)
    }

    func testReadSystemPowerWattsConsistentWithVoltsTimesAmps() {
        let volts = 20.3
        let amps = 0.12
        let watts = volts * amps
        let service = SMCService(connection: FakeSMCConnection(isOpen: true, keys: [
            "VD0R": fltKey(volts),
            "ID0R": fltKey(amps),
            "PDTR": fltKey(watts)
        ]))

        let power = service.readSystemPower()
        guard let power, let volts = power.volts, let amps = power.amps, let watts = power.watts else {
            return XCTFail("expected a full power report")
        }
        XCTAssertEqual(watts, volts * amps, accuracy: 0.0001)
    }

    func testReadSystemPowerPartialWattsOnlyStillReported() {
        let service = SMCService(connection: FakeSMCConnection(isOpen: true, keys: [
            "PDTR": fltKey(4.2)
        ]))

        let power = service.readSystemPower()
        XCTAssertEqual(power?.watts ?? 0, 4.2, accuracy: 0.0001)
        XCTAssertNil(power?.volts)
        XCTAssertNil(power?.amps)
    }
}
