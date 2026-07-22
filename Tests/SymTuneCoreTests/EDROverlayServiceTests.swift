import XCTest
@testable import SymTuneCore

final class MockEDROverlayService: EDROverlayServiceProtocol, @unchecked Sendable {
    var appliedHeadroom: [CGDirectDisplayID: Double] = [:]
    var applyError: Error?

    func applyExtendedBrightness(_ multiplier: Double, displayID: CGDirectDisplayID?) throws {
        if let applyError { throw applyError }
        let id = displayID ?? 1
        appliedHeadroom[id] = multiplier
    }

    func removeOverlay(for displayID: CGDirectDisplayID) {
        appliedHeadroom.removeValue(forKey: displayID)
    }

    func removeAllOverlays() {
        appliedHeadroom.removeAll()
    }

    func currentHeadroom(for displayID: CGDirectDisplayID) -> Double? {
        appliedHeadroom[displayID]
    }

    func systemEDRHeadroom(for displayID: CGDirectDisplayID) -> Double? {
        1.6
    }
}

final class EDROverlayServiceProtocolTests: XCTestCase {

    func testMockEDROverlayServiceApplyAndRemove() throws {
        let mock = MockEDROverlayService()
        XCTAssertNil(mock.currentHeadroom(for: 1))

        try mock.applyExtendedBrightness(1.3, displayID: 1)
        XCTAssertEqual(mock.currentHeadroom(for: 1), 1.3)
        XCTAssertEqual(mock.systemEDRHeadroom(for: 1), 1.6)

        mock.removeOverlay(for: 1)
        XCTAssertNil(mock.currentHeadroom(for: 1))
    }

    func testMockEDROverlayServiceRemoveAll() throws {
        let mock = MockEDROverlayService()
        try mock.applyExtendedBrightness(1.2, displayID: 1)
        try mock.applyExtendedBrightness(1.5, displayID: 2)
        XCTAssertEqual(mock.appliedHeadroom.count, 2)

        mock.removeAllOverlays()
        XCTAssertTrue(mock.appliedHeadroom.isEmpty)
    }

    func testMockEDROverlayServiceErrorHandling() {
        let mock = MockEDROverlayService()
        mock.applyError = TuneError.failed("EDR unsupported")

        XCTAssertThrowsError(try mock.applyExtendedBrightness(1.4, displayID: 1)) { error in
            guard case TuneError.failed(let msg) = error else {
                return XCTFail("expected TuneError.failed, got \(error)")
            }
            XCTAssertEqual(msg, "EDR unsupported")
        }
    }
}
