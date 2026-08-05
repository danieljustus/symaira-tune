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
    default:
        return false
    }
    return true
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
