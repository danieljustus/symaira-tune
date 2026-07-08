import Foundation

// All structs are `Codable`. The CLI and MCP layers encode them with
// `.convertToSnakeCase`, so a property `thermalPressure` is emitted as
// `thermal_pressure` for agent-friendly JSON.

// MARK: - Sensors

public struct SensorReading: Codable, Sendable, Equatable {
    public let key: String
    public let label: String
    public let celsius: Double

    public init(key: String, label: String, celsius: Double) {
        self.key = key
        self.label = label
        self.celsius = celsius
    }
}

public struct FanReading: Codable, Sendable, Equatable {
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

public struct ProfileSaved: Codable, Sendable {
    public let saved: String

    public init(saved: String) {
        self.saved = saved
    }
}

public struct ProfileList: Codable, Sendable {
    public let profiles: [TuneProfile]

    public init(profiles: [TuneProfile]) {
        self.profiles = profiles
    }
}

// MARK: - Capabilities (doctor)

public struct Capability: Codable, Sendable {
    public let id: String
    public let available: Bool
    /// `core` (Apache-2.0, this binary) or `pro` (needs the privileged helper).
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

// MARK: - Active Overrides

public struct ActiveOverrides: Codable, Sendable, Equatable {
    public let brightness: Double?
    public let dim: Double?
    public let warmth: Double?
    public let edrBrightness: Double?

    public init(
        brightness: Double? = nil,
        dim: Double? = nil,
        warmth: Double? = nil,
        edrBrightness: Double? = nil
    ) {
        self.brightness = brightness
        self.dim = dim
        self.warmth = warmth
        self.edrBrightness = edrBrightness
    }
}

// MARK: - Status Report

public struct StatusReport: Codable, Sendable {
    public let healthScore: Int
    public let healthScoreMsg: String
    public let recommendations: [String]
    public let activeOverrides: ActiveOverrides
    public let sensors: SensorReport
    public let battery: BatteryReport
    public let displays: DisplaysReport

    public init(
        healthScore: Int,
        healthScoreMsg: String,
        recommendations: [String],
        activeOverrides: ActiveOverrides,
        sensors: SensorReport,
        battery: BatteryReport,
        displays: DisplaysReport
    ) {
        self.healthScore = healthScore
        self.healthScoreMsg = healthScoreMsg
        self.recommendations = recommendations
        self.activeOverrides = activeOverrides
        self.sensors = sensors
        self.battery = battery
        self.displays = displays
    }
}

// MARK: - History Event

public struct HistoryEvent: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let action: String
    public let requestedValue: Double?
    public let clampedValue: Double?
    public let appliedValue: Double?
    public let result: String
    public let errorReason: String?

    public init(
        timestamp: Date = Date(),
        action: String,
        requestedValue: Double? = nil,
        clampedValue: Double? = nil,
        appliedValue: Double? = nil,
        result: String,
        errorReason: String? = nil
    ) {
        self.timestamp = timestamp
        self.action = action
        self.requestedValue = requestedValue
        self.clampedValue = clampedValue
        self.appliedValue = appliedValue
        self.result = result
        self.errorReason = errorReason
    }
}

