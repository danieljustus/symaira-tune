import Foundation
import SymTuneCore

/// Read-only JSON commands with no subcommand parsing. Returns `false` when
/// the command is not one of them, so the main dispatcher keeps handling it.
func runReadCommand(_ command: String, rest: [String], controller: TuneController) throws -> Bool {
    switch command {
    case "doctor":
        try emitJSON(controller.capabilities())
    case "sensors":
        try emitJSON(controller.sensorsReport())
    case "battery":
        try emitJSON(controller.batteryReport())
    case "displays":
        try emitJSON(controller.displaysReport())
    case "permissions":
        try emitJSON(controller.permissions())
    case "metrics":
        try runMetrics(rest, controller: controller)
    case "ai-usage":
        try runAIUsage(rest, controller: controller)
    case "processes", "top":
        try runProcesses(rest, controller: controller)
    default:
        return false
    }
    return true
}

/// `symtune processes` — which processes are using the most CPU or memory.
func runProcesses(_ args: [String], controller: TuneController) throws {
    if args.contains(where: { $0 == "--help" || $0 == "-h" }) {
        emit("Usage: symtune processes [--sort cpu|memory] [--limit N] [--json]")
        emit("")
        emit("Rank running processes by CPU or memory usage. CPU is a rate, so the")
        emit("command samples twice (about a second apart) before reporting. Processes")
        emit("owned by another user are counted but not readable without elevation.")
        return
    }

    var sort = ProcessSortKey.cpu
    var limit = ProcessUsageService.defaultLimit
    var wantsJSON = false
    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--json":
            wantsJSON = true
        case "--sort":
            index += 1
            guard index < args.count, let parsed = ProcessSortKey(rawValue: args[index]) else {
                throw TuneError.usage("processes: --sort expects 'cpu' or 'memory'")
            }
            sort = parsed
        case "--limit":
            index += 1
            guard index < args.count, let parsed = Int(args[index]), parsed > 0 else {
                throw TuneError.usage("processes: --limit expects a positive integer")
            }
            limit = parsed
        default:
            throw TuneError.usage("processes: unexpected argument '\(arg)'")
        }
        index += 1
    }

    // First sweep establishes the CPU baseline; without it every percentage
    // would be nil (or, worse, an average since boot).
    _ = controller.topProcesses(sortedBy: sort, limit: limit)
    Thread.sleep(forTimeInterval: 1.0)
    let report = controller.topProcesses(sortedBy: sort, limit: limit)

    if wantsJSON {
        try emitJSON(report)
        return
    }

    // Manual padding: `String(format:)` ignores width flags on `%@`.
    func column(_ text: String, _ width: Int, alignRight: Bool = false) -> String {
        let clipped = String(text.prefix(width))
        let padding = String(repeating: " ", count: max(0, width - clipped.count))
        return alignRight ? padding + clipped : clipped + padding
    }

    emit(column("PID", 8) + column("PROCESS", 34) + column("CPU %", 8, alignRight: true)
         + " " + column("MEMORY", 10, alignRight: true))
    emit(String(repeating: "-", count: 61))
    for process in report.processes {
        let cpu = process.cpuPercent.map { String(format: "%.1f", $0) } ?? "n/a"
        emit(column(String(process.pid), 8)
             + column(process.name, 34)
             + column(cpu, 8, alignRight: true)
             + " " + column(MetricFormatting.bytes(process.memoryBytes), 10, alignRight: true))
    }
    for note in report.notes {
        emitErr("note: \(note)")
    }
}

func runAIUsage(_ args: [String], controller: TuneController) throws {
    if args.contains(where: { $0 == "--help" || $0 == "-h" }) {
        emit("Usage: symtune ai-usage [--json]")
        emit("")
        emit("AI subscription/token usage per provider (OpenRouter, …). Read-only;")
        emit("no credentials are ever printed. --json emits the machine-readable")
        emit("form (same schema as the MCP get_ai_usage tool).")
        return
    }
    let wantsJSON = args.contains("--json")
    for arg in args where arg != "--json" {
        throw TuneError.usage("ai-usage: unexpected argument '\(arg)'")
    }
    let results = controller.aiUsageReport()
    if wantsJSON {
        try emitJSON(results)
        return
    }
    func fmt(_ value: Decimal?) -> String {
        value.map { String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "—"
    }
    for result in results {
        if let snapshot = result.snapshot {
            emit("\(snapshot.providerID) (source: \(snapshot.source)):")
            for meter in snapshot.meters {
                let reset = meter.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "—"
                emit("  \(meter.label): \(fmt(meter.used)) / \(fmt(meter.limit)) \(meter.unit.unitLabel) (resets \(reset))")
            }
            if let balance = snapshot.balance {
                emit("  Balance: \(String(format: "%.2f", NSDecimalNumber(decimal: balance).doubleValue)) \(snapshot.currency ?? "")")
            }
        } else {
            emit("\(result.providerID): not set up (\(result.error ?? "unknown"))")
        }
    }
}
