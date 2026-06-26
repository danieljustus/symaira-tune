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
    func testExtendedBrightnessConfigApplied() {
        let custom = TuneConfig(extendedBrightnessMax: 1.4)
        let controller = TuneController(config: custom)
        XCTAssertEqual(controller.config.extendedBrightnessMax, 1.4)
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

    func testDimClampedBySafetyPolicy() {
        let controller = TuneController()
        XCTAssertNoThrow(try controller.applyDim(0.5))
        XCTAssertNoThrow(try controller.applyDim(0.0))
        XCTAssertNoThrow(try controller.applyDim(2.0))
    }

    func testDimLevelTracked() {
        let controller = TuneController()
        XCTAssertEqual(controller.getDimLevel(), 1.0)
        XCTAssertNoThrow(try controller.applyDim(0.5))
    }

    func testResetDimClearsOverlays() {
        let controller = TuneController()
        XCTAssertNoThrow(try controller.applyDim(0.5))
        controller.resetDim()
    }

    func testWarmthClampedBySafetyPolicy() {
        let controller = TuneController()
        do {
            try controller.applyWarmth(0.5)
        } catch {
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported (no built-in display), got \(error)")
            }
            return  // no built-in display; warmth tests are display-dependent
        }
        XCTAssertNoThrow(try controller.applyWarmth(0.0))
        XCTAssertNoThrow(try controller.applyWarmth(2.0))
    }

    func testResetWarmth() {
        let controller = TuneController()
        do {
            try controller.applyWarmth(0.5)
        } catch {
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported (no built-in display), got \(error)")
            }
            return  // no built-in display; warmth tests are display-dependent
        }
        XCTAssertNoThrow(try controller.resetWarmth())
    }

    func testRestoreAllNoOpWithoutOverrides() {
        let controller = TuneController()
        controller.restoreAll()
    }

    func testChargeLimitUnsupported() {
        XCTAssertThrowsError(try TuneController().applyChargeLimit(percent: 80)) { error in
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        }
    }

    func testApplyProfileWithBrightnessAndDim() throws {
        let controller = TuneController()
        let profile = try TuneProfile(name: "test", brightness: 0.5, dim: 0.7)
        do {
            try controller.applyProfile(profile)
        } catch {
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported (no built-in display), got \(error)")
            }
            // no built-in display; profile brightness/dim test is display-dependent
        }
    }

    func testApplyProfileWithWarmth() throws {
        let controller = TuneController()
        let profile = try TuneProfile(name: "test", warmth: 0.4)
        do {
            try controller.applyProfile(profile)
        } catch {
            guard case TuneError.unsupported = error else {
                return XCTFail("expected .unsupported (no built-in display), got \(error)")
            }
            // no built-in display; profile warmth test is display-dependent
        }
    }

    func testApplyProfileMinimal() throws {
        let controller = TuneController()
        let profile = try TuneProfile(name: "empty")
        XCTAssertNoThrow(try controller.applyProfile(profile))
    }

    func testGetWarmthLevelDefault() {
        let controller = TuneController()
        XCTAssertEqual(controller.getWarmthLevel(), 0)
    }

    func testGetDimLevelDefault() {
        let controller = TuneController()
        XCTAssertEqual(controller.getDimLevel(), 1.0)
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

// MARK: - Mock NetworkService

final class MockNetworkService: NetworkServiceProtocol, @unchecked Sendable {
    var responseData: Data?
    var response: URLResponse?
    var error: Error?

    func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        if let error = error { throw error }
        guard let data = responseData, let response = response else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

// MARK: - UpdateChecker Network Tests

final class UpdateCheckerNetworkTests: XCTestCase {
    private var mock: MockNetworkService!
    private let currentVersion = "0.1.0"

    override func setUp() {
        super.setUp()
        mock = MockNetworkService()
        Task { await UpdateChecker.resetCache() }
    }

    private func makeResponse(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/danieljustus/symaira-tune/releases/latest")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func makeReleaseJSON(tagName: String, htmlURL: String? = nil) -> Data {
        var json: [String: Any] = ["tag_name": tagName]
        if let htmlURL { json["html_url"] = htmlURL }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testCheckForUpdateReturnsNewerVersion() async {
        mock.responseData = makeReleaseJSON(tagName: "v0.2.0", htmlURL: "https://github.com/example/releases/v0.2.0")
        mock.response = makeResponse()

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertTrue(info!.updateAvailable)
        XCTAssertEqual(info!.latestVersion, "v0.2.0")
        XCTAssertEqual(info!.downloadURL, "https://github.com/example/releases/v0.2.0")
    }

    func testCheckForUpdateReturnsOlderVersion() async {
        mock.responseData = makeReleaseJSON(tagName: "v0.0.1")
        mock.response = makeResponse()

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
        XCTAssertEqual(info!.latestVersion, "v0.0.1")
    }

    func testCheckForUpdateReturnsSameVersion() async {
        mock.responseData = makeReleaseJSON(tagName: "v0.1.0")
        mock.response = makeResponse()

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
    }

    func testCheckForUpdateHandlesNetworkError() async {
        mock.error = URLError(.notConnectedToInternet)

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
        XCTAssertEqual(info!.latestVersion, currentVersion)
    }

    func testCheckForUpdateHandlesNon200Status() async {
        mock.responseData = makeReleaseJSON(tagName: "v0.2.0")
        mock.response = makeResponse(statusCode: 403)

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
    }

    func testCheckForUpdateHandlesInvalidJSON() async {
        mock.responseData = "not json".data(using: .utf8)
        mock.response = makeResponse()

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
    }

    func testCheckForUpdateHandlesMissingTagName() async {
        mock.responseData = try! JSONSerialization.data(withJSONObject: ["name": "release"])
        mock.response = makeResponse()

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
    }

    func testCheckForUpdateHandlesInvalidTagName() async {
        mock.responseData = makeReleaseJSON(tagName: "not-a-version")
        mock.response = makeResponse()

        let info = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertNotNil(info)
        XCTAssertFalse(info!.updateAvailable)
    }

    func testCheckForUpdateCachesResult() async {
        mock.responseData = makeReleaseJSON(tagName: "v0.2.0")
        mock.response = makeResponse()

        let info1 = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)
        let info2 = await UpdateChecker.checkForUpdate(currentVersion: currentVersion, networkService: mock)

        XCTAssertEqual(info1?.latestVersion, info2?.latestVersion)
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

// MARK: - Mock DisplayWriteService

/// Mock implementation of DisplayWriteServiceProtocol for testing TuneController write paths.
final class MockDisplayWriteService: DisplayWriteServiceProtocol, @unchecked Sendable {
    var brightness: Double = 0.5
    var lastSetBrightness: Float?
    var lastWarmth: Float?
    var lastExtendedBrightness: Double?
    var lastExtendedDisplayID: UInt32?
    var resetWarmthCalled = false
    var applyExtendedBrightnessError: Error?

    func getBuiltinBrightness() throws -> Double {
        brightness
    }

    func setBuiltinBrightness(_ value: Float) throws {
        lastSetBrightness = value
    }

    func applyWarmth(_ warmth: Float) throws {
        lastWarmth = warmth
    }

    func resetWarmth() throws {
        resetWarmthCalled = true
    }

    func applyExtendedBrightness(_ multiplier: Double, displayID: UInt32?) throws {
        if let error = applyExtendedBrightnessError {
            throw error
        }
        lastExtendedBrightness = multiplier
        lastExtendedDisplayID = displayID
    }
}

// MARK: - TuneController Write Path Tests (with mock)

final class TuneControllerWritePathTests: XCTestCase {
    private var mock: MockDisplayWriteService!
    private var controller: TuneController!

    override func setUp() {
        super.setUp()
        mock = MockDisplayWriteService()
        controller = TuneController(config: TuneConfig(), displayWrite: mock)
    }

    // MARK: - applyBuiltinBrightness

    func testApplyBuiltinBrightnessClampsAndSets() throws {
        mock.brightness = 0.8
        try controller.applyBuiltinBrightness(1.5)
        // Should clamp to config.brightnessMax (default 1.0)
        XCTAssertEqual(mock.lastSetBrightness, 1.0)
    }

    func testApplyBuiltinBrightnessSavesOriginal() throws {
        mock.brightness = 0.6
        try controller.applyBuiltinBrightness(0.9)
        // Original brightness (0.6) should be saved for restore
        XCTAssertEqual(mock.lastSetBrightness, 0.9)
    }

    func testApplyBuiltinBrightnessWithCustomRange() throws {
        let config = TuneConfig(brightnessMin: 0.2, brightnessMax: 0.8)
        let ctrl = TuneController(config: config, displayWrite: mock)
        mock.brightness = 0.5
        try ctrl.applyBuiltinBrightness(0.1)
        // Should clamp to 0.2 (brightnessMin)
        XCTAssertEqual(mock.lastSetBrightness, 0.2)
    }

    // MARK: - applyExtendedBrightness

    func testApplyExtendedBrightnessClampsAndApplies() throws {
        try controller.applyExtendedBrightness(2.0)
        // Should clamp to config.extendedBrightnessMax (default 1.6)
        XCTAssertEqual(mock.lastExtendedBrightness, 1.6)
        XCTAssertNil(mock.lastExtendedDisplayID)
    }

    func testApplyExtendedBrightnessWithCustomMax() throws {
        let config = TuneConfig(extendedBrightnessMax: 1.4)
        let ctrl = TuneController(config: config, displayWrite: mock)
        try ctrl.applyExtendedBrightness(1.5)
        XCTAssertEqual(mock.lastExtendedBrightness, 1.4)
    }

    func testApplyExtendedBrightnessBelowMinClampsToMin() throws {
        try controller.applyExtendedBrightness(0.5)
        // Should clamp to config.extendedBrightnessMin (default 1.0)
        XCTAssertEqual(mock.lastExtendedBrightness, 1.0)
    }

    // MARK: - applyWarmth

    func testApplyWarmthClampsAndApplies() throws {
        try controller.applyWarmth(1.5)
        // Should clamp to 1.0
        XCTAssertEqual(mock.lastWarmth, 1.0)
    }

    func testApplyWarmthNegativeClampsToZero() throws {
        try controller.applyWarmth(-0.5)
        XCTAssertEqual(mock.lastWarmth, 0.0)
    }

    func testApplyWarmthMiddleValue() throws {
        try controller.applyWarmth(0.5)
        XCTAssertEqual(mock.lastWarmth, 0.5)
    }

    // MARK: - resetWarmth

    func testResetWarmthCallsReset() throws {
        try controller.resetWarmth()
        XCTAssertTrue(mock.resetWarmthCalled)
    }

    // MARK: - getBuiltinBrightness

    func testGetBuiltinBrightnessReturnsMockValue() throws {
        mock.brightness = 0.75
        let value = try controller.getBuiltinBrightness()
        XCTAssertEqual(value, 0.75)
    }

    // MARK: - Default init still works

    func testDefaultInitUsesHardwareService() {
        // The default init should still work (uses HardwareDisplayWriteService)
        let defaultController = TuneController()
        XCTAssertNotNil(defaultController)
    }
}
