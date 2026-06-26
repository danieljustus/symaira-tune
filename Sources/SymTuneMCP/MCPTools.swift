import Foundation
import SymTuneCore

// MARK: - Read-only capability / sensor tools

struct CapabilitiesTool: MCPTool, @unchecked Sendable {
    let name = "get_capabilities"
    let description = "Report tool version, host info, and which tuning capabilities are available."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.capabilities()
    }
}

struct SensorsTool: MCPTool, @unchecked Sendable {
    let name = "get_sensors"
    let description = "Read thermal pressure and (when available) temperatures and fan RPM."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.sensors_report()
    }
}

struct BatteryTool: MCPTool, @unchecked Sendable {
    let name = "get_battery"
    let description = "Read battery health: charge %, cycle count, capacity, condition."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.batteryReport()
    }
}

struct ListDisplaysTool: MCPTool, @unchecked Sendable {
    let name = "list_displays"
    let description = "List displays with EDR headroom (extended-brightness capability)."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.displaysReport()
    }
}

// MARK: - Keep-awake

struct KeepAwakeState: Encodable {
    let enabled: Bool
    let preventDisplaySleep: Bool
}

struct KeepAwakeTool: MCPTool, @unchecked Sendable {
    let name = "keep_awake"
    let description = "Prevent the Mac from idle-sleeping while the server runs."
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "enabled": ["type": "boolean"],
            "prevent_display_sleep": ["type": "boolean", "default": false],
        ],
        "required": ["enabled"],
    ]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        let enabled = arguments["enabled"] as? Bool ?? false
        let preventDisplaySleep = arguments["prevent_display_sleep"] as? Bool ?? false
        if enabled {
            if keepAwakeToken == nil {
                keepAwakeToken = try controller.beginKeepAwake(
                    reason: "symtune MCP keep_awake",
                    preventDisplaySleep: preventDisplaySleep
                )
            }
        } else if let token = keepAwakeToken {
            controller.endKeepAwake(token)
            keepAwakeToken = nil
        }
        return KeepAwakeState(enabled: keepAwakeToken != nil, preventDisplaySleep: preventDisplaySleep)
    }
}

// MARK: - Brightness / warmth / dim tools

struct GetBrightnessTool: MCPTool, @unchecked Sendable {
    let name = "get_brightness"
    let description = "Read the built-in display brightness (0.0–1.0)."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        BrightnessReadback(brightness: try controller.getBuiltinBrightness())
    }
}

struct SetBrightnessTool: MCPTool, @unchecked Sendable {
    let name = "set_brightness"
    let description = "Set built-in display brightness (0.0–1.0)."
    let inputSchema: [String: Any] = numberProperty(name: "value", minimum: 0.0, maximum: 1.0)

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.applyBuiltinBrightness(requireDouble(arguments["value"], name: "value"))
        return ApplyResult(applied: true)
    }
}

struct SetExtendedBrightnessTool: MCPTool, @unchecked Sendable {
    let name = "set_extended_brightness"
    let description = "Set extended/EDR brightness multiplier (1.0–1.6) via on-screen EDR layer."
    let inputSchema: [String: Any] = numberProperty(
        name: "value",
        minimum: SafetyPolicy.extendedBrightnessMin,
        maximum: SafetyPolicy.extendedBrightnessMax
    )

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.applyExtendedBrightness(requireDouble(arguments["value"], name: "value"))
        return ApplyResult(applied: true)
    }
}

struct SetWarmthTool: MCPTool, @unchecked Sendable {
    let name = "set_warmth"
    let description = "Set color temperature warmth (0.0=neutral, 1.0=max warm). Uses gamma LUT."
    let inputSchema: [String: Any] = numberProperty(name: "value", minimum: 0.0, maximum: 1.0)

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.applyWarmth(requireDouble(arguments["value"], name: "value"))
        return ApplyResult(applied: true)
    }
}

struct ResetWarmthTool: MCPTool, @unchecked Sendable {
    let name = "reset_warmth"
    let description = "Reset color temperature warmth to neutral (identity gamma)."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.resetWarmth()
        return ApplyResult(applied: true)
    }
}

struct SetDimTool: MCPTool, @unchecked Sendable {
    let name = "set_dim"
    let description = "Set software dim overlay (0.15=max dim, 1.0=no dim)."
    let inputSchema: [String: Any] = numberProperty(
        name: "value",
        minimum: SafetyPolicy.dimMin,
        maximum: SafetyPolicy.dimMax
    )

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.applyDim(requireDouble(arguments["value"], name: "value"))
        return ApplyResult(applied: true)
    }
}

struct ResetDimTool: MCPTool, @unchecked Sendable {
    let name = "reset_dim"
    let description = "Remove all dim overlays."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.resetDim()
        return ApplyResult(applied: true)
    }
}

struct RestoreTool: MCPTool, @unchecked Sendable {
    let name = "restore"
    let description = "Restore all overrides to system defaults."
    let inputSchema: [String: Any] = [:]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        controller.restoreAll()
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

// MARK: - Pro tools (require privileged helper)

struct SetFanTool: MCPTool, @unchecked Sendable {
    let name = "set_fan"
    let description = "Set fan speed as a fraction 0.0–1.0. Pro — requires the privileged helper."
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "fraction": ["type": "number", "minimum": SafetyPolicy.fanFractionMin, "maximum": SafetyPolicy.fanFractionMax],
        ],
        "required": ["fraction"],
    ]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.applyFan(fraction: requireDouble(arguments["fraction"], name: "fraction"))
        return ApplyResult(applied: false)
    }
}

struct SetChargeLimitTool: MCPTool, @unchecked Sendable {
    let name = "set_charge_limit"
    let description = "Hold battery charge at a target percent (50–100). Pro — requires the privileged helper."
    let inputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "percent": ["type": "integer", "minimum": SafetyPolicy.chargeLimitMin, "maximum": SafetyPolicy.chargeLimitMax],
        ],
        "required": ["percent"],
    ]

    func invoke(arguments: [String: Any], controller: TuneController, keepAwakeToken: inout KeepAwakeToken?) throws -> Encodable {
        try controller.applyChargeLimit(percent: requireInt(arguments["percent"], name: "percent"))
        return ApplyResult(applied: false)
    }
}

// MARK: - Schema helpers

private func numberProperty(name: String, minimum: Double, maximum: Double) -> [String: Any] {
    [
        "type": "object",
        "properties": [
            name: ["type": "number", "minimum": minimum, "maximum": maximum],
        ],
        "required": [name],
    ]
}
