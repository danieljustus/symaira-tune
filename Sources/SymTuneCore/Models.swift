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

public struct SensorReport: Codable, Sendable, Equatable {
    /// `nominal` | `fair` | `serious` | `critical` | `unknown`
    public let thermalPressure: String
    public let smcSupported: Bool
    public let temperatures: [SensorReading]
    public let fans: [FanReading]
    public let notes: [String]
}

// MARK: - Battery

public struct BatteryReport: Codable, Sendable, Equatable {
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
    /// Apple's own whole-percent figure from `system_profiler
    /// SPPowerDataType` ("Maximum Capacity", as shown in System Settings).
    /// Absent when the block cannot be read or parsed. This legitimately
    /// differs from `healthPercent` — see the README's battery section.
    public let appleMaximumCapacityPercent: Int?
    /// Apple's own "Condition" verdict from the same source (e.g. "Normal",
    /// "Replace Soon"). Absent when the block cannot be read or parsed.
    public let appleCondition: String?
    /// Whether the SMC exposes a charge-limit key on this Mac. This depends on
    /// the platform key probe (CHTE/CH0B/CHLC) and an SMC connection.
    public let chargeLimitSupported: Bool
    public let notes: [String]

    public init(
        present: Bool,
        charging: Bool?,
        externalConnected: Bool?,
        currentCapacityPercent: Int?,
        cycleCount: Int?,
        designCapacityMah: Int?,
        maxCapacityMah: Int?,
        healthPercent: Int?,
        temperatureCelsius: Double?,
        appleMaximumCapacityPercent: Int? = nil,
        appleCondition: String? = nil,
        chargeLimitSupported: Bool,
        notes: [String]
    ) {
        self.present = present
        self.charging = charging
        self.externalConnected = externalConnected
        self.currentCapacityPercent = currentCapacityPercent
        self.cycleCount = cycleCount
        self.designCapacityMah = designCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.healthPercent = healthPercent
        self.temperatureCelsius = temperatureCelsius
        self.appleMaximumCapacityPercent = appleMaximumCapacityPercent
        self.appleCondition = appleCondition
        self.chargeLimitSupported = chargeLimitSupported
        self.notes = notes
    }
}

// MARK: - Displays

public struct DisplayInfo: Codable, Sendable, Equatable {
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

public struct DisplaysReport: Codable, Sendable, Equatable {
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
    /// Capability tier: `core` for features shipped in the open binary.
    /// The previous `pro` tier has been removed; all features live in core.
    public let tier: String
    public let detail: String
}

public struct PermissionStatus: Codable, Sendable {
    /// True when the SMC connection is open. Fan and charge-limit writes still
    /// require the process to run with root privileges.
    public let privilegedHelperInstalled: Bool
    public let historyWritable: Bool?
    public let mcpMode: String?
    public let notes: [String]

    public init(privilegedHelperInstalled: Bool, historyWritable: Bool? = nil, mcpMode: String? = nil, notes: [String]) {
        self.privilegedHelperInstalled = privilegedHelperInstalled
        self.historyWritable = historyWritable
        self.mcpMode = mcpMode
        self.notes = notes
    }
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
    /// Active uniform fan fraction when fans are in manual mode.
    public let fanFraction: Double?
    /// Active charge limit percent, if a charge-limit key is set.
    public let chargeLimitPercent: Int?

    public init(
        brightness: Double? = nil,
        dim: Double? = nil,
        warmth: Double? = nil,
        edrBrightness: Double? = nil,
        fanFraction: Double? = nil,
        chargeLimitPercent: Int? = nil
    ) {
        self.brightness = brightness
        self.dim = dim
        self.warmth = warmth
        self.edrBrightness = edrBrightness
        self.fanFraction = fanFraction
        self.chargeLimitPercent = chargeLimitPercent
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

// MARK: - Keep-Awake Session

public struct KeepAwakeSession: Codable, Sendable, Equatable {
    public let active: Bool
    public let preventDisplaySleep: Bool
    public let startedAt: Date
    public let expiresAt: Date?
    public let reason: String

    public init(
        active: Bool,
        preventDisplaySleep: Bool,
        startedAt: Date,
        expiresAt: Date?,
        reason: String
    ) {
        self.active = active
        self.preventDisplaySleep = preventDisplaySleep
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.reason = reason
    }

    /// Convenience: an inactive (ended) session.
    public static let inactive = KeepAwakeSession(
        active: false,
        preventDisplaySleep: false,
        startedAt: Date(),
        expiresAt: nil,
        reason: ""
    )
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

// MARK: - System Metrics

public struct CPUReport: Codable, Sendable, Equatable {
    public let totalUtilization: Double?
    public let perCoreUtilization: [Double]
}

public struct MemoryReport: Codable, Sendable, Equatable {
    public let usedBytes: UInt64?
    public let freeBytes: UInt64?
    public let wiredBytes: UInt64?
    public let compressedBytes: UInt64?
    public let pressure: String?
}

public struct DiskReport: Codable, Sendable, Equatable {
    public let capacityBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
}

public struct NetworkInterfaceReport: Codable, Sendable, Equatable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let bytesInPerSecond: Double?
    public let bytesOutPerSecond: Double?
}

public struct NetworkReport: Codable, Sendable, Equatable {
    public let interfaces: [NetworkInterfaceReport]
    public let aggregateBytesIn: UInt64
    public let aggregateBytesOut: UInt64
    public let aggregateBytesInPerSecond: Double?
    public let aggregateBytesOutPerSecond: Double?
}

/// Live power draw from the SMC DC-in rail. Every field is optional: the
/// `VD0R`/`ID0R`/`PDTR` keys are not exposed on every Mac, and the whole
/// block is omitted from JSON when nothing is readable — no zeros, no guesses.
public struct PowerReport: Codable, Sendable, Equatable {
    /// DC-in rail voltage in volts (`VD0R`).
    public let volts: Double?
    /// DC-in rail current in amps (`ID0R`).
    public let amps: Double?
    /// DC-in rail power draw in watts (`PDTR`).
    public let watts: Double?

    public init(volts: Double? = nil, amps: Double? = nil, watts: Double? = nil) {
        self.volts = volts
        self.amps = amps
        self.watts = watts
    }
}

public struct SystemMetricsReport: Codable, Sendable, Equatable {
    public let cpu: CPUReport
    public let memory: MemoryReport
    public let disk: DiskReport?
    public let network: NetworkReport
    /// Live power draw; absent when the SMC does not expose the DC-in keys.
    public let power: PowerReport?
    public let notes: [String]
    public init(
        cpu: CPUReport,
        memory: MemoryReport,
        disk: DiskReport?,
        network: NetworkReport,
        power: PowerReport? = nil,
        notes: [String] = []
    ) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.power = power
        self.notes = notes
    }
}
