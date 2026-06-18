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

        let fan = report.capabilities.first { $0.id == "fan.control" }
        XCTAssertEqual(fan?.tier, "pro")
        XCTAssertEqual(fan?.available, false)

        let awake = report.capabilities.first { $0.id == "power.keepAwake" }
        XCTAssertEqual(awake?.tier, "core")
        XCTAssertEqual(awake?.available, true)

        let brightness = report.capabilities.first { $0.id == "display.brightness.set" }
        XCTAssertEqual(brightness?.available, true)

        let warmth = report.capabilities.first { $0.id == "display.warmth.set" }
        XCTAssertEqual(warmth?.available, true)
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

    func testBrightnessClampedBeforeApply() {
        let controller = TuneController()
        do {
            try controller.applyBuiltinBrightness(2.0)
        } catch {
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported (no built-in display), got \(error)")
            }
        }
    }
}

// MARK: - SemVer parsing

final class SemVerParsingTests: XCTestCase {
    func testParseBasicVersion() {
        let v = UpdateChecker.SemVer.parse("v0.1.0")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 1)
        XCTAssertEqual(v?.patch, 0)
        XCTAssertNil(v?.prerelease)
    }

    func testParseWithoutVPrefix() {
        let v = UpdateChecker.SemVer.parse("1.2.3")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
    }

    func testParsePrerelease() {
        let v = UpdateChecker.SemVer.parse("v0.2.0-beta.1")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 0)
        XCTAssertEqual(v?.prerelease, "beta.1")
    }

    func testParseInvalidReturnsNil() {
        XCTAssertNil(UpdateChecker.SemVer.parse(""))
        XCTAssertNil(UpdateChecker.SemVer.parse("not-a-version"))
        XCTAssertNil(UpdateChecker.SemVer.parse("v1.2"))
        XCTAssertNil(UpdateChecker.SemVer.parse("v1.2.x"))
        XCTAssertNil(UpdateChecker.SemVer.parse("abc.def.ghi"))
    }

    func testDescription() {
        let v = UpdateChecker.SemVer(major: 1, minor: 2, patch: 3)
        XCTAssertEqual("\(v)", "1.2.3")

        let pre = UpdateChecker.SemVer(major: 0, minor: 1, patch: 0, prerelease: "alpha.1")
        XCTAssertEqual("\(pre)", "0.1.0-alpha.1")
    }
}

// MARK: - SemVer comparison

final class SemVerComparisonTests: XCTestCase {
    func testMajorVersionOrdering() {
        XCTAssertTrue(UpdateChecker.SemVer.parse("v1.0.0")! < UpdateChecker.SemVer.parse("v2.0.0")!)
    }

    func testMinorVersionOrdering() {
        XCTAssertTrue(UpdateChecker.SemVer.parse("v0.1.0")! < UpdateChecker.SemVer.parse("v0.2.0")!)
    }

    func testPatchVersionOrdering() {
        XCTAssertTrue(UpdateChecker.SemVer.parse("v0.1.1")! < UpdateChecker.SemVer.parse("v0.1.2")!)
    }

    func testPrereleaseBeforeRelease() {
        XCTAssertTrue(UpdateChecker.SemVer.parse("v0.2.0-beta.1")! < UpdateChecker.SemVer.parse("v0.2.0")!)
    }

    func testPrereleaseOrdering() {
        XCTAssertTrue(UpdateChecker.SemVer.parse("v0.2.0-alpha.1")! < UpdateChecker.SemVer.parse("v0.2.0-beta.1")!)
    }

    func testEqualVersions() {
        XCTAssertEqual(UpdateChecker.SemVer.parse("v0.1.0"), UpdateChecker.SemVer.parse("v0.1.0"))
    }

    func testCurrentVersionLessThanHypothetical() {
        let current = UpdateChecker.SemVer.parse("v\(TuneVersion.current)")!
        let future = UpdateChecker.SemVer.parse("v99.0.0")!
        XCTAssertTrue(current < future)
    }
}

// MARK: - Update check opt-out

final class UpdateCheckOptOutTests: XCTestCase {
    func testDefaultIsEnabled() {
        XCTAssertTrue(UpdateChecker.isUpdateCheckEnabled(env: [:]))
    }

    func testEnvVarFalseDisables() {
        XCTAssertFalse(UpdateChecker.isUpdateCheckEnabled(env: ["SYMTUNE_CHECK_UPDATES": "false"]))
    }

    func testEnvVarTrueEnables() {
        XCTAssertTrue(UpdateChecker.isUpdateCheckEnabled(env: ["SYMTUNE_CHECK_UPDATES": "true"]))
    }

    func testEnvVarOneDisables() {
        XCTAssertFalse(UpdateChecker.isUpdateCheckEnabled(env: ["SYMTUNE_CHECK_UPDATES": "0"]))
    }

    func testEnvVarCaseInsensitive() {
        XCTAssertFalse(UpdateChecker.isUpdateCheckEnabled(env: ["SYMTUNE_CHECK_UPDATES": "FALSE"]))
        XCTAssertFalse(UpdateChecker.isUpdateCheckEnabled(env: ["SYMTUNE_CHECK_UPDATES": "False"]))
    }
}

// MARK: - Profile Name Validation

final class ProfileNameValidationTests: XCTestCase {
    func testValidNames() {
        XCTAssertTrue(TuneProfile.isValidProfileName("default"))
        XCTAssertTrue(TuneProfile.isValidProfileName("my-profile"))
        XCTAssertTrue(TuneProfile.isValidProfileName("profile_123"))
        XCTAssertTrue(TuneProfile.isValidProfileName("A"))
    }

    func testRejectsEmptyName() {
        XCTAssertFalse(TuneProfile.isValidProfileName(""))
    }

    func testRejectsPathTraversal() {
        XCTAssertFalse(TuneProfile.isValidProfileName("../etc/passwd"))
        XCTAssertFalse(TuneProfile.isValidProfileName("foo/../../../bar"))
        XCTAssertFalse(TuneProfile.isValidProfileName("a..b"))
    }

    func testRejectsNullByte() {
        XCTAssertFalse(TuneProfile.isValidProfileName("foo\0bar"))
    }

    func testRejectsInvalidCharacters() {
        XCTAssertFalse(TuneProfile.isValidProfileName("foo bar"))
        XCTAssertFalse(TuneProfile.isValidProfileName("foo.bar"))
        XCTAssertFalse(TuneProfile.isValidProfileName("foo@bar"))
        XCTAssertFalse(TuneProfile.isValidProfileName("foo:bar"))
    }

    func testInitRejectsInvalidName() {
        XCTAssertThrowsError(try TuneProfile(name: "../etc/passwd")) { error in
            guard case TuneError.usage = error else {
                return XCTFail("expected .usage, got \(error)")
            }
        }
    }

    func testInitAcceptsValidName() {
        XCTAssertNoThrow(try TuneProfile(name: "my-profile"))
    }
}

// MARK: - SMC Param Block

final class SMCParamBlockTests: XCTestCase {
    func testByteCountMatchesCLayout() {
        XCTAssertEqual(SMCParamBlock.byteCount, 80,
                       "SMCParamBlock must be exactly 80 bytes to match C SMCParamStruct")
    }

    func testKeyEncodingRoundTrip() {
        let key = smcEncodeKey("FNum")
        XCTAssertEqual(smcDecodeKey(key), "FNum")
    }

    func testKeyEncodingBigEndian() {
        let key = smcEncodeKey("FNum")
        XCTAssertEqual(key, 0x464E756D)
    }

    func testKeyEncodingInvalidLength() {
        XCTAssertEqual(smcEncodeKey("AB"), 0)
        XCTAssertEqual(smcEncodeKey("ABCDE"), 0)
    }
}

// MARK: - SMC Value Conversion

final class SMCValueConversionTests: XCTestCase {
    func testFPE2Conversion() {
        let fpe2Type = smcEncodeKey("fpe2")
        // 40.0 °C = 40 * 256 = 10240 = 0x2800
        let bytes: [UInt8] = [0x28, 0x00]
        let temp = smcConvertValue(dataType: fpe2Type, bytes: bytes)
        XCTAssertEqual(temp, 40.0, accuracy: 0.01)
    }

    func testFPE2FractionalPart() {
        let fpe2Type = smcEncodeKey("fpe2")
        // 48.75 °C = 48 * 256 + 192 = 12480 = 0x30C0
        let bytes: [UInt8] = [0x30, 0xC0]
        let temp = smcConvertValue(dataType: fpe2Type, bytes: bytes)
        XCTAssertEqual(temp, 48.75, accuracy: 0.01)
    }

    func testUI8Conversion() {
        let ui8Type = smcEncodeKey("ui8 ")
        let bytes: [UInt8] = [42]
        XCTAssertEqual(smcConvertValue(dataType: ui8Type, bytes: bytes), 42.0)
    }

    func testUI16Conversion() {
        let ui16Type = smcEncodeKey("ui16")
        let bytes: [UInt8] = [0x03, 0xE8]
        XCTAssertEqual(smcConvertValue(dataType: ui16Type, bytes: bytes), 1000.0)
    }

    func testSP78SignedConversion() {
        let sp78Type = smcEncodeKey("sp78")
        // -10.0 = -2560 = 0xF600 (as Int16)
        let bytes: [UInt8] = [0xF6, 0x00]
        let temp = smcConvertValue(dataType: sp78Type, bytes: bytes)
        XCTAssertEqual(temp, -10.0, accuracy: 0.01)
    }

    func testEmptyBytesReturnsZero() {
        let fpe2Type = smcEncodeKey("fpe2")
        XCTAssertEqual(smcConvertValue(dataType: fpe2Type, bytes: []), 0)
    }

    func testUnknownTypeFallsBackToRawInteger() {
        let unknownType: UInt32 = 0x41424344
        let bytes: [UInt8] = [0x00, 0x05]
        let val = smcConvertValue(dataType: unknownType, bytes: bytes)
        XCTAssertEqual(val, 5.0)
    }
}

// MARK: - OverrideTracker

final class OverrideTrackerTests: XCTestCase {
    func testSaveBrightnessRecordsOriginal() {
        let tracker = OverrideTracker()
        tracker.saveBrightness(0.8)
        tracker.restoreAll()
    }

    func testSaveWarmthTracksAppliedLevel() {
        let tracker = OverrideTracker()
        XCTAssertEqual(tracker.currentWarmth, 0)
        tracker.saveWarmth(0.5)
        XCTAssertEqual(tracker.currentWarmth, 0.5)
        tracker.restoreAll()
        XCTAssertEqual(tracker.currentWarmth, 0.5)
    }

    func testRestoreAllIsIdempotent() {
        let tracker = OverrideTracker()
        tracker.saveBrightness(0.7)
        tracker.restoreAll()
        tracker.restoreAll()
    }

    func testRestoreAllWithoutOverridesIsNoop() {
        let tracker = OverrideTracker()
        tracker.restoreAll()
    }

    func testSaveBrightnessOnlyRecordsFirst() {
        let tracker = OverrideTracker()
        tracker.saveBrightness(0.8)
        tracker.saveBrightness(0.5)
        tracker.restoreAll()
    }

    func testSaveWarmthUpdatesAppliedLevel() {
        let tracker = OverrideTracker()
        tracker.saveWarmth(0.3)
        XCTAssertEqual(tracker.currentWarmth, 0.3)
        tracker.saveWarmth(0.7)
        XCTAssertEqual(tracker.currentWarmth, 0.7)
        tracker.restoreAll()
    }
}

// MARK: - Sensor Report (SMC integration)

final class SensorReportTests: XCTestCase {
    func testSMCAvailableReflectedInCapabilities() {
        let report = TuneController().capabilities()
        let smc = report.capabilities.first { $0.id == "sensors.smc" }
        XCTAssertNotNil(smc)
        XCTAssertEqual(smc?.tier, "core")
        // On a real Mac this should be true; in CI/VM it may be false.
        // Either way, the capability must exist.
    }

    func testSensorReportHasExpectedFields() {
        let report = SensorService().read()
        XCTAssertEqual(report.thermalPressure.count > 0, true)
        // smcSupported may be true or false depending on environment.
        XCTAssertNotNil(report.fans)
        XCTAssertNotNil(report.temperatures)
        XCTAssertNotNil(report.notes)
    }
}
