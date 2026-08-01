import XCTest
import QuartzCore
@testable import SymTuneCore

/// Fake overlay that records routing without creating real NSWindows.
private final class FakeEDROverlay: EDROverlay {
    var removed = false

    init(displayID: CGDirectDisplayID) {
        super.init(displayID: displayID, screenFrame: .zero)
    }

    override func configure(screenFrame: NSRect) {
        // No real window creation in tests.
    }

    override func removeFromScreen() {
        removed = true
    }
}

final class EDROverlayServiceTests: XCTestCase {

    private let displayA: CGDirectDisplayID = 0x1000_0001
    private let displayB: CGDirectDisplayID = 0x1000_0002

    /// Service with a fake frame provider and a factory that returns fakes.
    private func makeService(
        frames: [CGDirectDisplayID: CGRect],
        factory: @escaping (CGDirectDisplayID, CGRect) -> EDROverlay
    ) -> EDROverlayService {
        EDROverlayService(
            screenFrameProvider: { frames[$0] },
            overlayFactory: factory
        )
    }

    private func fakeFactory() -> (EDROverlayService, () -> [FakeEDROverlay]) {
        var created: [FakeEDROverlay] = []
        let service = makeService(frames: [displayA: CGRect(x: 0, y: 0, width: 1920, height: 1080)]) { id, _ in
            let overlay = FakeEDROverlay(displayID: id)
            created.append(overlay)
            return overlay
        }
        return (service, { created })
    }

    // MARK: - Create / update routing

    func testApplyCreatesOverlayAndSetsHeadroom() throws {
        let (service, created) = fakeFactory()
        try service.applyExtendedBrightness(1.5, displayID: displayA)

        XCTAssertEqual(created().count, 1)
        let headroom = try XCTUnwrap(created().first?.headroom)
        XCTAssertEqual(headroom, 1.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(service.currentHeadroom(for: displayA)), 1.5, accuracy: 0.0001)
    }

    func testApplyUpdatesExistingOverlayInsteadOfCreatingAnother() throws {
        let (service, created) = fakeFactory()
        try service.applyExtendedBrightness(1.3, displayID: displayA)
        try service.applyExtendedBrightness(1.6, displayID: displayA)

        XCTAssertEqual(created().count, 1, "second apply must reuse the existing overlay")
        XCTAssertEqual(try XCTUnwrap(created().first?.headroom), 1.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(service.currentHeadroom(for: displayA)), 1.6, accuracy: 0.0001)
    }

    // MARK: - Error paths

    func testApplyThrowsWhenScreenFrameMissing() {
        let service = makeService(frames: [:]) { id, _ in FakeEDROverlay(displayID: id) }
        XCTAssertThrowsError(try service.applyExtendedBrightness(1.5, displayID: displayA)) { error in
            guard case TuneError.failed = error else {
                return XCTFail("expected TuneError.failed, got \(error)")
            }
        }
    }

    func testApplyThrowsWhenMultiplierBelowMinimum() {
        let (service, _) = fakeFactory()
        XCTAssertThrowsError(try service.applyExtendedBrightness(0.99, displayID: displayA)) { error in
            guard case TuneError.usage = error else {
                return XCTFail("expected TuneError.usage, got \(error)")
            }
        }
    }

    func testApplyThrowsWhenMultiplierAboveMaximum() {
        let (service, _) = fakeFactory()
        XCTAssertThrowsError(try service.applyExtendedBrightness(1.61, displayID: displayA)) { error in
            guard case TuneError.usage = error else {
                return XCTFail("expected TuneError.usage, got \(error)")
            }
        }
    }

    func testApplyWithoutDisplayIDThrowsOnThisHost() {
        // No display session is guaranteed in unit tests: either the built-in
        // display lookup fails or the injected frame provider returns nil —
        // both must surface as an error, never a crash.
        let (service, _) = fakeFactory()
        XCTAssertThrowsError(try service.applyExtendedBrightness(1.5))
    }

    // MARK: - Removal

    func testRemoveOverlayClearsHeadroomAndRemovesFromScreen() throws {
        let (service, created) = fakeFactory()
        try service.applyExtendedBrightness(1.5, displayID: displayA)
        XCTAssertNotNil(service.currentHeadroom(for: displayA))

        service.removeOverlay(for: displayA)

        XCTAssertNil(service.currentHeadroom(for: displayA))
        XCTAssertTrue(created().first?.removed == true)
    }

    func testApplyingNeutralMultiplierRemovesOverlayAndAllowsReapply() throws {
        let (service, created) = fakeFactory()
        try service.applyExtendedBrightness(1.4, displayID: displayA)
        let firstOverlay = try XCTUnwrap(created().first)

        try service.applyExtendedBrightness(SafetyPolicy.extendedBrightnessMin, displayID: displayA)

        XCTAssertNil(service.currentHeadroom(for: displayA))
        XCTAssertTrue(firstOverlay.removed)

        try service.applyExtendedBrightness(1.2, displayID: displayA)

        XCTAssertEqual(created().count, 2)
        XCTAssertEqual(try XCTUnwrap(created().last?.headroom), 1.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(service.currentHeadroom(for: displayA)), 1.2, accuracy: 0.0001)
    }

    func testRemoveAllOverlaysRemovesEverything() throws {
        var frames: [CGDirectDisplayID: CGRect] = [:]
        var created: [FakeEDROverlay] = []
        let service = EDROverlayService(
            screenFrameProvider: { frames[$0] },
            overlayFactory: { id, _ in
                let overlay = FakeEDROverlay(displayID: id)
                created.append(overlay)
                return overlay
            }
        )
        frames[displayA] = .zero
        frames[displayB] = .zero

        try service.applyExtendedBrightness(1.4, displayID: displayA)
        try service.applyExtendedBrightness(1.2, displayID: displayB)
        XCTAssertEqual(created.count, 2)

        service.removeAllOverlays()

        XCTAssertNil(service.currentHeadroom(for: displayA))
        XCTAssertNil(service.currentHeadroom(for: displayB))
        XCTAssertTrue(created.allSatisfy { $0.removed })
    }

    func testCurrentHeadroomIsNilWithoutOverlay() {
        let (service, _) = fakeFactory()
        XCTAssertNil(service.currentHeadroom(for: displayA))
    }

    func testMetalLayerConfigurationIsTransparentWhileRetainingEDR() throws {
        let layer = CAMetalLayer()
        let pixelFormat = try XCTUnwrap(MTLPixelFormat(rawValue: 80))

        EDROverlay.configureMetalLayer(
            layer,
            pixelFormat: pixelFormat,
            frameSize: CGSize(width: 1920, height: 1080),
            contentsScale: 2.0
        )

        let backgroundColor = try XCTUnwrap(layer.backgroundColor)
        XCTAssertTrue(layer.wantsExtendedDynamicRangeContent)
        XCTAssertFalse(layer.isOpaque)
        XCTAssertEqual(backgroundColor.alpha, 0, accuracy: 0.0001)
        XCTAssertEqual(layer.opacity, 0, accuracy: 0.0001)
    }

    func testSystemEDRHeadroomIsNilForUnknownDisplay() {
        let (service, _) = fakeFactory()
        // No real display session: the production lookup cannot resolve a
        // fake display ID, so this must be nil rather than crash.
        XCTAssertNil(service.systemEDRHeadroom(for: displayA))
    }
}
