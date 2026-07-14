import Foundation
import SymTuneCore
import SymTuneMCP

let usage = """
symtune \(TuneVersion.current) — tune your Mac (thermals, brightness, power) from the CLI and for AI agents.

USAGE
  symtune <command> [options]

READ COMMANDS
  doctor                 Capabilities, host info, and recommendations (JSON).
  status [--json] [--watch [--interval <duration>]]
                         System health status snapshot (Score, overrides, sensors, battery).
  history [--json]       Write operations history log.
  sensors                Thermal pressure + (when available) temps/fan RPM (JSON).
  battery                Battery health: charge %, cycles, capacity, condition (JSON).
  displays               Displays with EDR headroom / extended-brightness capability (JSON).
  permissions            Permission & SMC write status (JSON).

POWER
  awake [--display] [--seconds N]
                         Prevent idle sleep. Holds until N seconds elapse, or until
                         Ctrl-C if --seconds is omitted. --display also keeps the
                         screen on.

WRITE COMMANDS
  brightness get                Read built-in display brightness (0.0–1.0)
  brightness set <0.0-1.0>     Built-in display brightness
  extbright set <1.0-1.6>     Extended/EDR brightness multiplier
  dim set <0.15-1.0>          Software dim overlay
  dim reset                   Remove all dim overlays
  warmth set <0.0-1.0>        Color temperature warmth (gamma)
  warmth reset                Reset warmth to neutral
  restore                     Restore all overrides to defaults
  fan set <0.0-1.0>           Fan speed fraction (requires sudo)
  fan auto                    Return fans to firmware automatic control
  battery-limit set <50-100>  Hold charge at target percent (requires sudo)
  battery-limit clear         Re-enable charging (requires sudo)
  profile save <name>         Save current settings as a profile
  profile load <name>         Apply a saved profile
  profile list                List saved profiles
  profile delete <name>       Delete a saved profile

PRIVILEGED SMC WRITES
  Fan and battery-limit commands write to the Apple SMC. They must be run as
  root, e.g. `sudo symtune fan set 0.5`. Values are clamped to safe ranges and
  original settings are restored on normal exit or Ctrl-C.

AGENTS
  serve                  Run the MCP server over stdio.

  version [--check-for-updates] | help

  --check-for-updates    Check GitHub for a newer version (non-blocking, writes notices to stderr).
"""

func emitJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func emitErr(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

func runVersion(checkForUpdates: Bool) {
    emit("symtune \(TuneVersion.current)")
    guard checkForUpdates else { return }
    // Fire-and-forget update check: never block the CLI, emit notices to stderr
    // so scripts parsing stdout still get clean version output.
    Task.detached {
        if let info = await UpdateChecker.checkForUpdate(),
           info.updateAvailable,
           let url = info.downloadURL
        {
            emitErr("A new version (\(info.latestVersion)) is available. Download: \(url)")
        }
    }
}

/// Pull the first parseable Double out of the remaining args (accepts an
/// optional leading `set`), e.g. `extbright set 1.4` or `dim 0.5`.
func parseValue(_ args: [String], command: String) throws -> Double {
    for arg in args where arg != "set" {
        if let value = Double(arg) { return value }
    }
    throw TuneError.usage("\(command): expected a numeric value, e.g. `symtune \(command) set 1.4`")
}

func parseInt(_ args: [String], command: String) throws -> Int {
    for arg in args where arg != "set" {
        if let value = Int(arg) { return value }
    }
    throw TuneError.usage("\(command): expected an integer value, e.g. `symtune \(command) set 80`")
}

func runAwake(_ args: [String], controller: TuneController) throws {
    var seconds: Double?
    var preventDisplaySleep = false
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--display":
            preventDisplaySleep = true
        case "--seconds", "-s":
            index += 1
            guard index < args.count, let value = Double(args[index]) else {
                throw TuneError.usage("awake --seconds requires a number.")
            }
            seconds = value
        default:
            throw TuneError.usage("awake: unknown option '\(args[index])'.")
        }
        index += 1
    }

    let token = try controller.beginKeepAwake(reason: "symtune awake", preventDisplaySleep: preventDisplaySleep)
    defer { controller.endKeepAwake(token) }
    if let seconds {
        emitErr("symtune: holding wake assertion for \(seconds)s…")
        Thread.sleep(forTimeInterval: seconds)
    } else {
        emitErr("symtune: holding wake assertion (Ctrl-C to release)…")
        RunLoop.current.run()
    }
}

func runProfile(_ args: [String], controller: TuneController) throws {
    guard let subcommand = args.first else {
        throw TuneError.usage("profile: expected subcommand (save, load, list, delete).")
    }
    let rest = Array(args.dropFirst())

    switch subcommand {
    case "save":
        guard let name = rest.first else {
            throw TuneError.usage("profile save: expected a name.")
        }
        let brightness = try? controller.getBuiltinBrightness()
        let profile = try TuneProfile(
            name: name,
            brightness: brightness,
            dim: controller.getDimLevel(),
            warmth: controller.getWarmthLevel()
        )
        try controller.saveProfile(profile)
        try emitJSON(ProfileSaved(saved: name))
    case "load":
        guard let name = rest.first else {
            throw TuneError.usage("profile load: expected a name.")
        }
        let profile = try controller.loadProfile(name: name)
        try controller.applyProfile(profile)
        try emitJSON(ApplyResult(applied: true))
    case "list":
        let profiles = controller.listProfiles()
        try emitJSON(ProfileList(profiles: profiles))
    case "delete":
        guard let name = rest.first else {
            throw TuneError.usage("profile delete: expected a name.")
        }
        try controller.deleteProfile(name: name)
        try emitJSON(ApplyResult(applied: true))
    default:
        throw TuneError.usage("profile: unknown subcommand '\(subcommand)'.")
    }
}
func emitNDJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func runStatus(_ args: [String], controller: TuneController) throws {
    var isWatch = false
    var interval: TimeInterval = 1.0
    var isJson = false

    var index = 0
    while index < args.count {
        switch args[index] {
        case "--watch":
            isWatch = true
        case "--interval":
            index += 1
            guard index < args.count else {
                throw TuneError.usage("status: --interval requires a value.")
            }
            interval = try DurationParser.parse(args[index])
        case "--json":
            isJson = true
        default:
            throw TuneError.usage("status: unknown option '\(args[index])'")
        }
        index += 1
    }

    if isWatch {
        while true {
            let report = controller.statusReport()
            try emitNDJSON(report)
            Thread.sleep(forTimeInterval: interval)
        }
    } else {
        let report = controller.statusReport()
        if isJson {
            try emitJSON(report)
        } else {
            emit("symtune health: \(report.healthScoreMsg) (Score: \(report.healthScore)/100)")
            emit("\nRecommendations:")
            for rec in report.recommendations {
                emit("- \(rec)")
            }
            emit("\nActive Overrides:")
            let o = report.activeOverrides
            var anyOverride = false
            if let b = o.brightness {
                emit("- Brightness: \(Int(b * 100))%")
                anyOverride = true
            }
            if let d = o.dim {
                emit("- Software Dim: \(Int(d * 100))%")
                anyOverride = true
            }
            if let w = o.warmth {
                emit("- Warmth: \(Int(w * 100))%")
                anyOverride = true
            }
            if let edr = o.edrBrightness {
                emit("- Extended EDR Brightness: \(String(format: "%.1f", edr))x")
                anyOverride = true
            }
            if let fan = o.fanFraction {
                emit("- Fan: \(Int(fan * 100))%")
                anyOverride = true
            }
            if let charge = o.chargeLimitPercent {
                emit("- Charge Limit: \(charge)%")
                anyOverride = true
            }
            if !anyOverride {
                emit("- None")
            }
        }
    }
}

func runHistory(_ args: [String], controller: TuneController) throws {
    var isJson = false
    for arg in args {
        if arg == "--json" {
            isJson = true
        } else {
            throw TuneError.usage("history: unknown option '\(arg)'")
        }
    }

    let events = controller.getHistory()
    if isJson {
        try emitJSON(events)
    } else {
        if events.isEmpty {
            emit("No history events recorded.")
            return
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        emit(String(format: "%-20@ %-16@ %-10@ %-10@ %-10@ %-10@ %@",
                    "Timestamp" as NSString,
                    "Action" as NSString,
                    "Requested" as NSString,
                    "Clamped" as NSString,
                    "Applied" as NSString,
                    "Result" as NSString,
                    "Reason/Error" as NSString))
        emit(String(repeating: "-", count: 90))
        for event in events {
            let req = event.requestedValue != nil ? String(format: "%.2f", event.requestedValue!) : "n/a"
            let clm = event.clampedValue != nil ? String(format: "%.2f", event.clampedValue!) : "n/a"
            let app = event.appliedValue != nil ? String(format: "%.2f", event.appliedValue!) : "n/a"
            let err = event.errorReason ?? ""
            emit(String(format: "%-20@ %-16@ %-10@ %-10@ %-10@ %-10@ %@",
                        df.string(from: event.timestamp) as NSString,
                        event.action as NSString,
                        req as NSString,
                        clm as NSString,
                        app as NSString,
                        event.result as NSString,
                        err as NSString))
        }
    }
}

private func runBrightness(_ rest: [String], controller: TuneController) throws {
    if rest.first == "get" || rest.isEmpty {
        let brightness = try controller.getBuiltinBrightness()
        try emitJSON(BrightnessReadback(brightness: brightness))
    } else {
        try controller.applyBuiltinBrightness(try parseValue(rest, command: "brightness"))
        try emitJSON(ApplyResult(applied: true))
    }
}

private func runDim(_ rest: [String], controller: TuneController) throws {
    if rest.first == "reset" {
        controller.resetDim()
        try emitJSON(ApplyResult(applied: true))
    } else {
        try controller.applyDim(try parseValue(rest, command: "dim"))
        try emitJSON(ApplyResult(applied: true))
    }
}

private func runWarmth(_ rest: [String], controller: TuneController) throws {
    if rest.first == "reset" {
        try controller.resetWarmth()
        try emitJSON(ApplyResult(applied: true))
    } else {
        try controller.applyWarmth(try parseValue(rest, command: "warmth"))
        try emitJSON(ApplyResult(applied: true))
    }
}

private func runExtBright(_ rest: [String], controller: TuneController) throws {
    try controller.applyExtendedBrightness(try parseValue(rest, command: "extbright"))
    try emitJSON(ApplyResult(applied: true))
}

private func runFan(_ rest: [String], controller: TuneController) throws {
    if rest.first == "auto" {
        try controller.restoreFanAuto()
        try emitJSON(ApplyResult(applied: true))
    } else {
        try controller.applyFan(fraction: try parseValue(rest, command: "fan"))
        try emitJSON(ApplyResult(applied: true))
    }
}

private func runBatteryLimit(_ rest: [String], controller: TuneController) throws {
    if rest.first == "clear" {
        try controller.clearChargeLimit()
        try emitJSON(ApplyResult(applied: true))
    } else {
        try controller.applyChargeLimit(percent: try parseInt(rest, command: "battery-limit"))
        try emitJSON(ApplyResult(applied: true))
    }
}

func runMain() -> Int32 {
    guard let command = CommandLine.arguments.dropFirst().first else {
        emit(usage)
        return ExitCode.ok.rawValue
    }
    let rest = Array(CommandLine.arguments.dropFirst(2))
    let controller = TuneController(config: ConfigPaths().loadConfig())

    do {
        switch command {
        case "serve":
            try MCPServer(controller: controller).run()
        case "status":
            try runStatus(rest, controller: controller)
        case "history":
            try runHistory(rest, controller: controller)
        case "doctor":
            try emitJSON(controller.capabilities())
        case "sensors":
            try emitJSON(controller.sensors_report())
        case "battery":
            try emitJSON(controller.batteryReport())
        case "displays":
            try emitJSON(controller.displaysReport())
        case "permissions":
            try emitJSON(controller.permissions())
        case "awake":
            try runAwake(rest, controller: controller)
        case "brightness":
            try runBrightness(rest, controller: controller)
        case "extbright":
            try runExtBright(rest, controller: controller)
        case "dim":
            try runDim(rest, controller: controller)
        case "warmth":
            try runWarmth(rest, controller: controller)
        case "restore":
            controller.restoreAll()
            try emitJSON(ApplyResult(applied: true))
        case "profile":
            try runProfile(rest, controller: controller)
        case "fan":
            try runFan(rest, controller: controller)
        case "battery-limit":
            try runBatteryLimit(rest, controller: controller)
        case "version", "--version", "-v":
            runVersion(checkForUpdates: rest.contains("--check-for-updates"))
        case "help", "--help", "-h":
            emit(usage)
        default:
            emitErr("symtune: unknown command '\(command)'")
            emit(usage)
            return ExitCode.usage.rawValue
        }
        return ExitCode.ok.rawValue
    } catch let error as TuneError {
        emitErr("symtune: \(error.description)")
        return error.exitCode
    } catch {
        let report: ErrorReport
        if FileHandle.standardOutput.isTty {
            report = ErrorReport(
                error: "\(type(of: error))",
                message: String(reflecting: error),
                localized: error.localizedDescription
            )
        } else {
            report = ErrorReport(
                error: "\(type(of: error))",
                message: String(reflecting: error),
                localized: error.localizedDescription
            )
        }
        if let json = try? JSONEncoder().encode(report),
           let string = String(data: json, encoding: .utf8) {
            emitErr("symtune: \(string)")
        } else {
            emitErr("symtune: \(String(reflecting: error))")
        }
        return ExitCode.error.rawValue
    }
}

struct ErrorReport: Codable {
    let error: String
    let message: String
    let localized: String
}

extension FileHandle {
    fileprivate var isTty: Bool {
        isStandardOutput() && isatty(fileno(stdout)) == 1
    }

    fileprivate func isStandardOutput() -> Bool {
        self === FileHandle.standardOutput
    }
}

exit(runMain())
