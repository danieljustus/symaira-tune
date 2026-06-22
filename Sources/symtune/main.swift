import Foundation
import SymTuneCore
import SymTuneMCP

let usage = """
symtune \(TuneVersion.current) — tune your Mac (thermals, brightness, power) from the CLI and for AI agents.

USAGE
  symtune <command> [options]

READ COMMANDS (v0.1)
  doctor                 Capabilities, host info, and recommendations (JSON).
  sensors                Thermal pressure + (when available) temps/fan RPM (JSON).
  battery                Battery health: charge %, cycles, capacity, condition (JSON).
  displays               Displays with EDR headroom / extended-brightness capability (JSON).
  permissions            Permission & privileged-helper status (JSON).

POWER
  awake [--display] [--seconds N]
                         Prevent idle sleep. Holds until N seconds elapse, or until
                         Ctrl-C if --seconds is omitted. --display also keeps the
                         screen on.

WRITE COMMANDS (planned / Pro — see docs/roadmap.md)
  brightness get                Read built-in display brightness (0.0–1.0)
  brightness set <0.0-1.0>     Built-in display brightness          (v0.1)
  extbright set <1.0-1.6>      Extended/EDR brightness multiplier   (v0.1)
  dim set <0.15-1.0>           Software dim overlay                 (v0.1)
  dim reset                    Remove all dim overlays              (v0.1)
  warmth set <0.0-1.0>         Color temperature warmth (gamma)     (v0.1)
  warmth reset                 Reset warmth to neutral              (v0.1)
  restore                      Restore all overrides to defaults    (v0.1)
  profile save <name>          Save current settings as a profile  (v0.1)
  profile load <name>          Apply a saved profile               (v0.1)
  profile list                 List saved profiles                 (v0.1)
  profile delete <name>        Delete a saved profile              (v0.1)
  fan set <0.0-1.0>            Fan speed fraction                   (Pro: needs helper)
  battery-limit set <50-100>   Hold charge at target percent        (Pro: needs helper)

AGENTS
  serve                  Run the MCP server over stdio.

  version [--check-for-updates] | help
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
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        if let info = await UpdateChecker.checkForUpdate(),
           info.updateAvailable,
           let url = info.downloadURL
        {
            emit("A new version (\(info.latestVersion)) is available. Download: \(url)")
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
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
            if rest.first == "get" || rest.isEmpty {
                let brightness = try controller.getBuiltinBrightness()
                try emitJSON(BrightnessReadback(brightness: brightness))
            } else {
                try controller.applyBuiltinBrightness(try parseValue(rest, command: "brightness"))
                try emitJSON(ApplyResult(applied: true))
            }
        case "extbright":
            try controller.applyExtendedBrightness(try parseValue(rest, command: "extbright"))
            try emitJSON(ApplyResult(applied: true))
        case "dim":
            if rest.first == "reset" {
                controller.resetDim()
                try emitJSON(ApplyResult(applied: true))
            } else {
                try controller.applyDim(try parseValue(rest, command: "dim"))
                try emitJSON(ApplyResult(applied: true))
            }
        case "warmth":
            if rest.first == "reset" {
                try controller.resetWarmth()
                try emitJSON(ApplyResult(applied: true))
            } else {
                try controller.applyWarmth(try parseValue(rest, command: "warmth"))
                try emitJSON(ApplyResult(applied: true))
            }
        case "restore":
            controller.restoreAll()
            try emitJSON(ApplyResult(applied: true))
        case "profile":
            try runProfile(rest, controller: controller)
        case "fan":
            try controller.applyFan(fraction: try parseValue(rest, command: "fan"))
        case "battery-limit":
            try controller.applyChargeLimit(percent: try parseInt(rest, command: "battery-limit"))
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
        emitErr("symtune: \(error.localizedDescription)")
        return ExitCode.error.rawValue
    }
}

exit(runMain())
