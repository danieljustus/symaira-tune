import Foundation

/// Facade over the individual services. Both the CLI and the MCP server talk to
/// the controller only — they never touch services directly. This is also where
/// the safety policy and (future) restore-on-exit bookkeeping live.
public final class TuneController: Sendable {
    private let sensors = SensorService()
    private let battery = BatteryService()
    private let displays = DisplayService()
    private let power = PowerService()
    private let dimOverlay = DimOverlay()
    private let edrOverlay = EDROverlayService()
    private let displayWrite: any DisplayWriteServiceProtocol
    private let profiles: ProfileService
    public let config: TuneConfig
    private let restoreTracker: OverrideTracker
    nonisolated(unsafe) private var helperClient: (any SMCHelperProtocol)?

    public init(
        config: TuneConfig = TuneConfig(),
        displayWrite: (any DisplayWriteServiceProtocol)? = nil
    ) {
        self.config = config
        self.displayWrite = displayWrite ?? HardwareDisplayWriteService(
            displayService: displays,
            edrOverlay: edrOverlay
        )
        self.profiles = ProfileService(dataDir: ConfigPaths().dataDir)
        self.restoreTracker = OverrideTracker(displayService: displays, edrOverlay: edrOverlay)
        restoreTracker.registerSignalHandlers()
    }

    deinit {
        restoreTracker.restoreAll()
        dimOverlay.removeAllOverlays()
        edrOverlay.removeAllOverlays()
    }

    // MARK: - Reads

    public func sensors_report() -> SensorReport { sensors.read() }

    public func sensorsReport() -> SensorReport { sensors_report() }

    public func batteryReport() -> BatteryReport { battery.read() }

    public func displaysReport() -> DisplaysReport { displays.list() }

    public func permissions() -> PermissionStatus {
        let helperInstalled = helperClient != nil
        return PermissionStatus(
            privilegedHelperInstalled: helperInstalled,
            notes: [
                helperInstalled
                    ? "Privileged SMC helper is installed and ready for fan/charge writes."
                    : "Privileged SMC helper not detected. Fan and charge-limit writes require the Pro helper.",
            ]
        )
    }

    public func capabilities() -> CapabilityReport {
        let batteryPresent = battery.read().present
        let edrCapable = displays.anyEDRCapable()

        let caps: [Capability] = [
            Capability(id: "sensors.thermalPressure", available: true, tier: "core",
                       detail: "Coarse thermal pressure from ProcessInfo (nominal…critical)."),
            Capability(id: "sensors.smc", available: sensors.smcAvailable, tier: "core",
                       detail: sensors.smcAvailable
                           ? "Detailed die temps & fan RPM via AppleSMC IOKit (unprivileged)."
                           : "SMC connection unavailable — detailed sensors not accessible."),
            Capability(id: "battery.read", available: batteryPresent, tier: "core",
                       detail: batteryPresent ? "AppleSmartBattery health readout." : "No battery present."),
            Capability(id: "display.edr.read", available: edrCapable, tier: "core",
                       detail: edrCapable ? "At least one display reports EDR headroom." : "No EDR-capable display detected."),
            Capability(id: "display.brightness.extended.set", available: edrCapable, tier: "core",
                       detail: edrCapable
                           ? "Extended/EDR brightness via on-screen EDR layer, clamped 1.0–1.6."
                           : "No EDR-capable display detected — extended brightness unavailable."),
            Capability(id: "display.dim.set", available: true, tier: "core",
                       detail: "Sub-minimum software dim overlay via transparent NSWindow."),
            Capability(id: "display.brightness.set", available: true, tier: "core",
                       detail: "Built-in display brightness get/set via DisplayServices/IOKit."),
            Capability(id: "display.warmth.set", available: true, tier: "core",
                       detail: "Color temperature warmth via CGSetDisplayTransferByTable gamma LUT."),
            Capability(id: "power.keepAwake", available: true, tier: "core",
                       detail: "Prevent idle sleep via IOKit power assertion."),
            Capability(id: "fan.control", available: false, tier: "pro",
                       detail: "Fan curves / fixed RPM — requires privileged SMC helper."),
            Capability(id: "battery.chargeLimit", available: false, tier: "pro",
                       detail: "Hold charge at a target percent — requires privileged SMC helper."),
        ]

        var recommendations: [String] = []
        if !edrCapable {
            recommendations.append("No EDR-capable display detected; extended brightness will be unavailable here.")
        }
        if !batteryPresent {
            recommendations.append("No battery detected; battery features are not applicable on this Mac.")
        }
        if recommendations.isEmpty {
            recommendations.append("Core read features are ready. Run `symtune serve` to expose them over MCP.")
        }

        return CapabilityReport(
            tool: "symtune",
            version: TuneVersion.current,
            macosVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            capabilities: caps,
            permissions: permissions(),
            recommendations: recommendations
        )
    }

    // MARK: - Keep awake

    public func beginKeepAwake(reason: String, preventDisplaySleep: Bool) throws -> KeepAwakeToken {
        try power.begin(reason: reason, preventDisplaySleep: preventDisplaySleep)
    }

    public func endKeepAwake(_ token: KeepAwakeToken) {
        power.end(token)
    }

    // MARK: - Write surface (v0.2 core)

    public func getBuiltinBrightness() throws -> Double {
        try displayWrite.getBuiltinBrightness()
    }

    public func applyBuiltinBrightness(_ value: Double) throws {
        let original = try? displayWrite.getBuiltinBrightness()
        if let original { restoreTracker.saveBrightness(Float(original)) }
        let clamped = SafetyPolicy.clamp(value, config.brightnessMin, config.brightnessMax)
        try displayWrite.setBuiltinBrightness(Float(clamped))
    }

    public func applyExtendedBrightness(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, config.extendedBrightnessMin, config.extendedBrightnessMax)
        // Capture the original system headroom before the first override so restore-on-exit
        // can return the display to its pre-symtune EDR level instead of SDR (1.0).
        restoreTracker.saveOriginalEDRHeadroom(edrOverlay)
        restoreTracker.saveEDRBrightness(clamped)
        try displayWrite.applyExtendedBrightness(clamped, displayID: nil)
    }

    public func applyDim(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, config.dimMin, config.dimMax)
        dimOverlay.applyDim(Float(clamped))
    }

    public func resetDim() {
        dimOverlay.removeAllOverlays()
    }

    public func getDimLevel() -> Double {
        Double(dimOverlay.dimLevel)
    }

    public func getWarmthLevel() -> Double {
        Double(restoreTracker.currentWarmth)
    }

    public func applyWarmth(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, 0.0, 1.0)
        restoreTracker.saveWarmth(Float(clamped))
        try displayWrite.applyWarmth(Float(clamped))
    }

    public func resetWarmth() throws {
        try displayWrite.resetWarmth()
    }

    public func restoreAll() {
        restoreTracker.restoreAll()
    }

    // MARK: - Profiles

    public func saveProfile(_ profile: TuneProfile) throws {
        try profiles.saveProfile(profile)
    }

    public func loadProfile(name: String) throws -> TuneProfile {
        try profiles.loadProfile(name: name)
    }

    public func listProfiles() -> [TuneProfile] {
        profiles.listProfiles()
    }

    public func deleteProfile(name: String) throws {
        try profiles.deleteProfile(name: name)
    }

    public func applyProfile(_ profile: TuneProfile) throws {
        if let brightness = profile.brightness {
            try applyBuiltinBrightness(brightness)
        }
        if let dim = profile.dim {
            try applyDim(dim)
        }
        if let warmth = profile.warmth {
            try applyWarmth(warmth)
        }
    }

    // MARK: - Rules

    public func saveRules(_ rules: [TuneRule]) throws {
        try profiles.saveRules(rules)
    }

    public func loadRules() -> [TuneRule] {
        profiles.loadRules()
    }

    public func addRule(_ rule: TuneRule) throws {
        try profiles.addRule(rule)
    }

    public func removeRule(id: String) throws {
        try profiles.removeRule(id: id)
    }

    public func applyFan(fraction: Double) throws {
        let clamped = SafetyPolicy.clamp(fraction, config.fanFractionMin, config.fanFractionMax)
        guard let helper = helperClient else {
            throw TuneError.unsupported(
                "fan control requires the privileged SMC helper (Pro tier)."
            )
        }
        try helper.setFanFraction(clamped)
    }

    public func applyChargeLimit(percent: Int) throws {
        let clamped = SafetyPolicy.clamp(percent, config.chargeLimitMin, config.chargeLimitMax)
        guard let helper = helperClient else {
            throw TuneError.unsupported(
                "charge limit requires the privileged SMC helper (Pro tier)."
            )
        }
        try helper.setChargeLimit(clamped)
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
