import XCTest
@testable import SymTuneCore

final class SafetyPolicyTests: XCTestCase {
    func testClampWithinRange() {
        XCTAssertEqual(SafetyPolicy.clamp(1.3, 1.0, 1.6), 1.3)
    }

    func testClampBelowLower() {
        XCTAssertEqual(SafetyPolicy.clamp(0.5, 1.0, 1.6), 1.0)
    }

    func testClampAboveUpper() {
        XCTAssertEqual(SafetyPolicy.clamp(2.0, 1.0, 1.6), 1.6)
    }

    func testDimNeverFullyBlack() {
        XCTAssertEqual(SafetyPolicy.clamp(0.0, SafetyPolicy.dimMin, SafetyPolicy.dimMax), SafetyPolicy.dimMin)
        XCTAssertGreaterThan(SafetyPolicy.dimMin, 0.0)
    }

    func testChargeLimitFloor() {
        XCTAssertEqual(SafetyPolicy.clamp(10, SafetyPolicy.chargeLimitMin, SafetyPolicy.chargeLimitMax),
                       SafetyPolicy.chargeLimitMin)
    }
}

final class CapabilityTests: XCTestCase {
    func testCapabilitiesShape() {
        let report = TuneController().capabilities()
        XCTAssertEqual(report.tool, "symtune")
        XCTAssertEqual(report.version, TuneVersion.current)
        XCTAssertFalse(report.capabilities.isEmpty)

        // Fan/charge must be advertised as Pro tier and unavailable in v0.1.
        let fan = report.capabilities.first { $0.id == "fan.control" }
        XCTAssertEqual(fan?.tier, "pro")
        XCTAssertEqual(fan?.available, false)

        // Keep-awake is a core capability that is available.
        let awake = report.capabilities.first { $0.id == "power.keepAwake" }
        XCTAssertEqual(awake?.tier, "core")
        XCTAssertEqual(awake?.available, true)
    }
}

final class SensorTests: XCTestCase {
    func testThermalPressureIsKnownLabel() {
        let label = SensorService.thermalPressureLabel()
        XCTAssertTrue(["nominal", "fair", "serious", "critical", "unknown"].contains(label))
    }
}

final class WriteSurfaceTests: XCTestCase {
    func testExtendedBrightnessNotImplemented() {
        XCTAssertThrowsError(try TuneController().applyExtendedBrightness(1.4)) { error in
            guard case TuneError.notImplemented = error else {
                return XCTFail("expected .notImplemented, got \(error)")
            }
        }
    }

    func testFanControlUnsupported() {
        XCTAssertThrowsError(try TuneController().applyFan(fraction: 0.5)) { error in
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        }
    }
}
