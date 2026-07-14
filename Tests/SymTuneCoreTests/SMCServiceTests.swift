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
        let raw = val.bitPattern.bigEndian
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
}
