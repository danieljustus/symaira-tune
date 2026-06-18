import Foundation

// All structs are `Codable`. The CLI and MCP layers encode them with
// `.convertToSnakeCase`, so a property `thermalPressure` is emitted as
// `thermal_pressure` for agent-friendly JSON.

// MARK: - Sensors

public struct SensorReading: Codable, Sendable {
    public let key: String
    public let label: String
    public let celsius: Double

    public init(key: String, label: String, celsius: Double) {
        self.key = key
        self.label = label
        self.celsius = celsius
    }
}

public struct FanReading: Codable, Sendable {
    public let index: Int
    public let label: String
    public let rpm: Int
    public let minRpm: Int?
    public let maxRpm: Int?

    public init(index: Int, label: String, rpm: Int, minRpm: Int?, maxRpm: Int?) {
        self.index = index
        self.label = label
        self.rpm = rpm
        self.minRpm = minRpm
        self.maxRpm = maxRpm
    }
}

public struct SensorReport: Codable, Sendable {
    /// `nominal` | `fair` | `serious` | `critical` | `unknown`
    public let thermalPressure: String
    public let smcSupported: Bool
    public let temperatures: [SensorReading]
    public let fans: [FanReading]
    public let notes: [String]
}

// MARK: - Battery

public struct BatteryReport: Codable, Sendable {
    public let present: Bool
    public let charging: Bool?
    public let externalConnected: Bool?
    public let currentCapacityPercent: Int?
    public let cycleCount: Int?
    public let designCapacityMah: Int?
    public let maxCapacityMah: Int?
    /// maxCapacity / designCapacity, in percent. ~100 on a healthy battery.
    public let healthPercent: Int?
    public let temperatureCelsius: Double?
    /// Whether a user-set charge limit can be applied. `false` in the core
    /// build — this needs the privileged Pro helper (see commercial-boundary.md).
    public let chargeLimitSupported: Bool
    public let notes: [String]
}

// MARK: - Displays

public struct DisplayInfo: Codable, Sendable {
    public let name: String
    public let displayID: UInt32
    public let isBuiltin: Bool?
    /// Current max EDR headroom (1.0 = no extended range available right now).
    public let maxEDRHeadroom: Double
    /// Headroom the panel *could* provide (drives the extended-brightness cap).
    public let potentialEDRHeadroom: Double
    public let edrCapable: Bool
    public let backingScaleFactor: Double
}

public struct DisplaysReport: Codable, Sendable {
    public let displays: [DisplayInfo]
    public let notes: [String]
}

public struct BrightnessReadback: Codable, Sendable {
    public let brightness: Double
    public let notes: [String]

    public init(brightness: Double, notes: [String] = []) {
        self.brightness = brightness
        self.notes = notes
    }
}

public struct ApplyResult: Codable, Sendable {
    public let applied: Bool

    public init(applied: Bool) {
        self.applied = applied
    }
}

// MARK: - Capabilities (doctor)

public struct Capability: Codable, Sendable {
    public let id: String
    public let available: Bool
    /// `core` (MIT, this binary) or `pro` (needs the privileged helper).
    public let tier: String
    public let detail: String
}

public struct PermissionStatus: Codable, Sendable {
    /// The privileged SMC helper that fan/charge writes will require. Planned —
    /// always `false` in v0.1.
    public let privilegedHelperInstalled: Bool
    public let notes: [String]
}

public struct CapabilityReport: Codable, Sendable {
    public let tool: String
    public let version: String
    public let macosVersion: String
    public let architecture: String
    public let capabilities: [Capability]
    public let permissions: PermissionStatus
    public let recommendations: [String]
}
