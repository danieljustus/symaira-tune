import Foundation
import SymTuneCore

// MARK: - Read-only capability / sensor tools

struct CapabilitiesTool: MCPTool, @unchecked Sendable {
    let name = "get_capabilities"
    let description = "Report tool version, host info, and which tuning capabilities are available."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.capabilities()
    }
}

struct SensorsTool: MCPTool, @unchecked Sendable {
    let name = "get_sensors"
    let description = "Read thermal pressure and (when available) temperatures and fan RPM."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.sensorsReport()
    }
}

struct BatteryTool: MCPTool, @unchecked Sendable {
    let name = "get_battery"
    let description = "Read battery health: charge %, cycle count, capacity, condition — plus Apple's own Maximum Capacity/Condition when available."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.batteryReport()
    }
}

struct ListDisplaysTool: MCPTool, @unchecked Sendable {
    let name = "list_displays"
    let description = "List displays with EDR headroom (extended-brightness capability)."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.displaysReport()
    }
}

struct MetricsTool: MCPTool, @unchecked Sendable {
    let name = "get_system_metrics"
    let description = "Read system metrics: CPU utilization, memory pressure, disk usage, network throughput, and live power draw (volts/amps/watts, when the SMC exposes them)."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.metricsReport()
    }
}

// MARK: - Keep-awake (session-level)

struct KeepAwakeTool: MCPTool, @unchecked Sendable {
    let name = "keep_awake"
    let description = "Start or stop a keep-awake session. Prevents idle/system sleep and optionally display sleep. Runs indefinitely without duration_seconds. Returns full session state."

    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "enabled": ["type": "boolean", "description": "Set to true to start a session, false to end it."],
                "prevent_display_sleep": ["type": "boolean", "default": false, "description": "When true, also prevent display sleep."],
                "duration_seconds": ["type": "number", "description": "Optional session duration in seconds. Omit for an indefinite session."],
            ],
            "required": ["enabled"],
        ]
    }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        let enabled = arguments["enabled"] as? Bool ?? false
        let preventDisplaySleep = arguments["prevent_display_sleep"] as? Bool ?? false

        if enabled {
            let duration = arguments["duration_seconds"] as? Double
            return try controller.beginKeepAwakeSession(
                duration: duration,
                preventDisplaySleep: preventDisplaySleep,
                reason: "symtune MCP keep_awake"
            )
        } else {
            controller.endKeepAwakeSession()
            return KeepAwakeSession.inactive
        }
    }
}

struct KeepAwakeStatusTool: MCPTool, @unchecked Sendable {
    let name = "keep_awake_status"
    let description = "Return the current keep-awake session state (active, type, remaining time, reason)."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.keepAwakeSessionStatus()
    }
}

// MARK: - Brightness / warmth / dim tools (read-only)

struct GetBrightnessTool: MCPTool, @unchecked Sendable {
    let name = "get_brightness"
    let description = "Read the built-in display brightness (0.0–1.0)."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        BrightnessReadback(brightness: try controller.getBuiltinBrightness())
    }
}

// MARK: - Generic write tool (driven by WriteCommand descriptor)

struct WriteCommandTool: MCPTool, @unchecked Sendable {
    let descriptor: WriteCommand

    var name: String { descriptor.mcpName }
    var description: String { descriptor.description }
    var isReadOnly: Bool { false }

    var inputSchema: [String: Any] {
        guard descriptor.isContinuous, let min = descriptor.minimum, let max = descriptor.maximum else {
            return [:]
        }
        let argName = descriptor.mcpArgName
        if descriptor.valueType == .integer {
            return [
                "type": "object",
                "properties": [
                    argName: ["type": "integer", "minimum": Int(min), "maximum": Int(max)],
                ],
                "required": [argName],
            ]
        } else {
            return [
                "type": "object",
                "properties": [
                    argName: ["type": "number", "minimum": min, "maximum": max],
                ],
                "required": [argName],
            ]
        }
    }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        if descriptor.isContinuous {
            if descriptor.valueType == .integer {
                let intVal = try requireInt(arguments[descriptor.mcpArgName], name: descriptor.mcpArgName)
                try descriptor.apply(controller, Double(intVal))
            } else {
                let doubleVal = try requireDouble(arguments[descriptor.mcpArgName], name: descriptor.mcpArgName)
                try descriptor.apply(controller, doubleVal)
            }
        } else {
            try descriptor.apply(controller, 0)
        }
        return ApplyResult(applied: true)
    }
}

// MARK: - Profile tools

struct SaveProfileTool: MCPTool, @unchecked Sendable {
    let name = "save_profile"
    let description = "Save current settings as a named profile."
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"],
    ]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        guard let name = arguments["name"] as? String else {
            throw TuneError.usage("save_profile requires a name.")
        }
        let brightness = try? controller.getBuiltinBrightness()
        let profile = try TuneProfile(
            name: name,
            brightness: brightness,
            dim: controller.getDimLevel(),
            warmth: controller.getWarmthLevel()
        )
        try controller.saveProfile(profile)
        return ProfileSaved(saved: name)
    }
}

struct LoadProfileTool: MCPTool, @unchecked Sendable {
    let name = "load_profile"
    let description = "Apply a saved profile by name."
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"],
    ]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        guard let name = arguments["name"] as? String else {
            throw TuneError.usage("load_profile requires a name.")
        }
        let profile = try controller.loadProfile(name: name)
        try controller.applyProfile(profile)
        return ApplyResult(applied: true)
    }
}

struct ListProfilesTool: MCPTool, @unchecked Sendable {
    let name = "list_profiles"
    let description = "List all saved profiles."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        ProfileList(profiles: controller.listProfiles())
    }
}

struct DeleteProfileTool: MCPTool, @unchecked Sendable {
    let name = "delete_profile"
    let description = "Delete a saved profile by name."
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"],
    ]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        guard let name = arguments["name"] as? String else {
            throw TuneError.usage("delete_profile requires a name.")
        }
        try controller.deleteProfile(name: name)
        return ApplyResult(applied: true)
    }
}

// MARK: - Status / history tools

struct GetStatusTool: MCPTool, @unchecked Sendable {
    let name = "get_status"
    let description = "Get the consolidated health status snapshot of the system, including score, recommendations, overrides, and raw reports."
    let inputSchema: [String: Any] = [:]
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.statusReport()
    }
}

struct GetHistoryTool: MCPTool, @unchecked Sendable {
    let name = "get_history"
    let description = "Retrieve the write operations history log."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "Maximum number of events to return (default 100)."],
            ],
        ]
    }
    var isReadOnly: Bool { true }

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        let limit = arguments["limit"] as? Int ?? 100
        return controller.getHistory(limit: limit)
    }
}
