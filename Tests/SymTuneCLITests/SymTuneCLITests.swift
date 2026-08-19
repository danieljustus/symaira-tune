import XCTest

final class SymTuneCLITests: XCTestCase {

    /// Path to the built symtune binary.
    /// The test target uses the PRODUCT_BUNDLE_IDENTIFIER build setting
    /// injected by SPM to find the binary relative to the test bundle.
    var symtuneBinary: String {
        // SPM places the built product one directory up from the test bundle.
        let binDir = productsDirectory
        return binDir.appendingPathComponent("symtune").path
    }

    /// Returns the products directory (where the test bundle and symtune live).
    var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("Could not locate the products directory — not running within an XCTest bundle?")
    }

    // MARK: - --help / -h on subcommands

    func testFanHelp() throws {
        let output = try runCommand(args: ["fan", "--help"])
        XCTAssert(output.contains("Usage: symtune fan"))
        XCTAssert(output.contains("<0.0-1.0>"))
    }

    func testFanHelpShort() throws {
        let output = try runCommand(args: ["fan", "-h"])
        XCTAssert(output.contains("Usage: symtune fan"))
    }

    func testDimHelp() throws {
        let output = try runCommand(args: ["dim", "--help"])
        XCTAssert(output.contains("Usage: symtune dim"))
    }

    func testWarmthHelp() throws {
        let output = try runCommand(args: ["warmth", "--help"])
        XCTAssert(output.contains("Usage: symtune warmth"))
    }

    func testBatteryLimitHelp() throws {
        let output = try runCommand(args: ["battery-limit", "--help"])
        XCTAssert(output.contains("Usage: symtune battery-limit"))
    }

    func testMetricsHelp() throws {
        let output = try runCommand(args: ["metrics", "--help"])
        XCTAssert(output.contains("Usage: symtune metrics"))
        XCTAssert(output.contains("system metrics"))
    }

    func testMetricsHelpShort() throws {
        let output = try runCommand(args: ["metrics", "-h"])
        XCTAssert(output.contains("Usage: symtune metrics"))
    }

    // MARK: Unknown-flag rejection

    func testFanUnknownFlag() throws {
        let output = try runCommand(args: ["fan", "--bogus"], expectFailure: true)
        XCTAssert(output.contains("unexpected argument"))
        XCTAssert(output.contains("--bogus"))
    }

    func testDimUnknownFlag() throws {
        let output = try runCommand(args: ["dim", "set", "--invalid"], expectFailure: true)
        XCTAssert(output.contains("unexpected argument"))
        XCTAssert(output.contains("--invalid"))
    }

    func testWarmthUnknownFlag() throws {
        let output = try runCommand(args: ["warmth", "--junk"], expectFailure: true)
        XCTAssert(output.contains("unexpected argument"))
        XCTAssert(output.contains("--junk"))
    }

    func testBatteryLimitUnknownFlag() throws {
        let output = try runCommand(args: ["battery-limit", "--unknown"], expectFailure: true)
        XCTAssert(output.contains("unexpected argument"))
        XCTAssert(output.contains("--unknown"))
    }

    func testMetricsUnknownFlag() throws {
        let output = try runCommand(args: ["metrics", "--bogus"], expectFailure: true)
        XCTAssert(output.contains("unexpected argument"))
        XCTAssert(output.contains("--bogus"))
    }

    func testMetricsJSON() throws {
        let output = try runCommand(args: ["metrics"])
        XCTAssert(output.contains("cpu"))
        XCTAssert(output.contains("memory"))
        XCTAssert(output.contains("network"))
    }

    func testAIUsageHelp() throws {
        let output = try runCommand(args: ["ai-usage", "--help"])
        XCTAssert(output.contains("ai-usage"))
        XCTAssert(output.contains("--json"))
    }

    func testAIUsageUnknownFlag() throws {
        _ = try runCommand(args: ["ai-usage", "--nope"], expectFailure: true)
    }

    func testAIUsageJSONListsProviders() throws {
        // No key configured on test machines → provider listed as not set up.
        let output = try runCommand(args: ["ai-usage", "--json"])
        XCTAssert(output.contains("openrouter"))
        XCTAssert(output.contains("provider_id"))
    }

    // MARK: - Always-JSON read commands (doctor, sensors, battery, displays, permissions)
    //
    // These five commands take no options: they should honour --help/-h
    // instead of running, and reject any other argument with a usage error
    // (exit code 2) instead of silently ignoring it.

    private static let alwaysJSONCommands = ["doctor", "sensors", "battery", "displays", "permissions"]

    func testAlwaysJSONCommandsHelp() throws {
        for command in Self.alwaysJSONCommands {
            let output = try runCommand(args: [command, "--help"])
            XCTAssert(output.contains("Usage: symtune \(command)"), "\(command) --help: \(output)")
            // Help output must not be the JSON report.
            XCTAssertFalse(output.contains("{"), "\(command) --help printed JSON instead of help: \(output)")
        }
    }

    func testAlwaysJSONCommandsHelpShort() throws {
        for command in Self.alwaysJSONCommands {
            let output = try runCommand(args: [command, "-h"])
            XCTAssert(output.contains("Usage: symtune \(command)"), "\(command) -h: \(output)")
            XCTAssertFalse(output.contains("{"), "\(command) -h printed JSON instead of help: \(output)")
        }
    }

    func testAlwaysJSONCommandsUnknownFlag() throws {
        for command in Self.alwaysJSONCommands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: symtuneBinary)
            process.arguments = [command, "--bogus"]
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            XCTAssertEqual(process.terminationStatus, 2,
                            "\(command) --bogus: expected ExitCode.usage (2), got \(process.terminationStatus). stderr: \(errorOutput)")
            XCTAssert(errorOutput.contains("unexpected argument"), "\(command) --bogus: \(errorOutput)")
            XCTAssert(errorOutput.contains("--bogus"), "\(command) --bogus: \(errorOutput)")
        }
    }

    func testDoctorJSON() throws {
        let output = try runCommand(args: ["doctor"])
        XCTAssert(output.contains("{"))
    }

    // MARK: - Unified --json contract (issue #315)
    //
    // Every read command accepts --json. The six always-JSON commands
    // (doctor, sensors, battery, displays, permissions, metrics) already
    // only have a machine form; --json must be a recognized no-op there,
    // not rejected by the #314 unexpected-argument check.

    private static let sixAlwaysJSONCommands = alwaysJSONCommands + ["metrics"]

    func testAlwaysJSONCommandsAcceptJSONFlagWithoutRejection() throws {
        for command in Self.sixAlwaysJSONCommands {
            let output = try runCommand(args: [command, "--json"])
            XCTAssert(output.contains("{"), "\(command) --json: expected JSON output, got: \(output)")
            XCTAssertFalse(output.contains("unexpected argument"),
                            "\(command) --json: flag should be a no-op, not rejected. Output: \(output)")
        }
    }

    func testAlwaysJSONCommandsJSONFlagIsNoOp() throws {
        // --json must not change the shape of the output: same top-level
        // keys with and without the flag.
        for command in Self.sixAlwaysJSONCommands {
            let plain = try runCommand(args: [command])
            let withFlag = try runCommand(args: [command, "--json"])

            guard let plainData = plain.data(using: .utf8),
                  let flagData = withFlag.data(using: .utf8),
                  let plainJSON = try? JSONSerialization.jsonObject(with: plainData) as? [String: Any],
                  let flagJSON = try? JSONSerialization.jsonObject(with: flagData) as? [String: Any] else {
                XCTFail("\(command): could not parse plain/--json output as a JSON object. plain: \(plain), --json: \(withFlag)")
                continue
            }
            XCTAssertEqual(Set(plainJSON.keys), Set(flagJSON.keys),
                            "\(command) --json: top-level keys should match the plain output")
        }
    }

    func testAlwaysJSONCommandsStillRejectOtherUnknownFlags() throws {
        // --json is a recognized no-op, but genuinely unknown flags must
        // still be rejected even when --json is also present.
        for command in Self.sixAlwaysJSONCommands {
            let output = try runCommand(args: [command, "--json", "--bogus"], expectFailure: true)
            XCTAssert(output.contains("unexpected argument"), "\(command) --json --bogus: \(output)")
            XCTAssert(output.contains("--bogus"), "\(command) --json --bogus: \(output)")
        }
    }

    // MARK: - Helpers

    /// Run `symtune` with the given arguments and return stderr (merged with stdout).
    /// - Parameters:
    ///   - args: Arguments to pass to the binary.
    ///   - expectFailure: If true, the process is expected to exit with a non-zero code.
    /// - Returns: The combined stdout+stderr output of the process.
    @discardableResult
    private func runCommand(args: [String], expectFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: symtuneBinary)
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        let combined = output + errorOutput

        if expectFailure {
            XCTAssertNotEqual(process.terminationStatus, 0,
                              "Expected failure but process succeeded. args: \(args)")
        } else {
            XCTAssertEqual(process.terminationStatus, 0,
                           "Process failed. args: \(args), stderr: \(errorOutput)")
        }

        return combined
    }
}
