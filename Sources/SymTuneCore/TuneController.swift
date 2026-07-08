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

    public let dataDir: URL
    private let historyService: HistoryService
    private let powerLock = NSLock()
    nonisolated(unsafe) private var activeTokensCount = 0

    public init(
        config: TuneConfig = TuneConfig(),
        displayWrite: (any DisplayWriteServiceProtocol)? = nil,
        dataDir: URL? = nil
    ) {
        self.config = config
        self.displayWrite = displayWrite ?? HardwareDisplayWriteService(
            displayService: displays,
            edrOverlay: edrOverlay
        )
        let resolvedDataDir = dataDir ?? ConfigPaths().dataDir
        self.dataDir = resolvedDataDir
        self.profiles = ProfileService(dataDir: resolvedDataDir)
        self.historyService = HistoryService(dataDir: resolvedDataDir)
        self.restoreTracker = OverrideTracker(displayService: displays, edrOverlay: edrOverlay)
        restoreTracker.registerSignalHandlers()
    }

    deinit {
        restoreTracker.restoreAll()
        dimOverlay.removeAllOverlays()
        edrOverlay.removeAllOverlays()
    }

    // MARK: - History log helper

    private func logHistory(
        action: String,
        requested: Double? = nil,
        clamped: Double? = nil,
        applied: Double? = nil,
        result: String,
        error: Error? = nil
    ) {
        let reason = error != nil ? "\(error!)" : nil
        let event = HistoryEvent(
            timestamp: Date(),
            action: action,
            requestedValue: requested,
            clampedValue: clamped,
            appliedValue: applied,
            result: result,
            errorReason: reason
        )
        historyService.logEvent(event)
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
        let token = try power.begin(reason: reason, preventDisplaySleep: preventDisplaySleep)
        powerLock.lock()
        activeTokensCount += 1
        powerLock.unlock()
        return token
    }

    public func endKeepAwake(_ token: KeepAwakeToken) {
        power.end(token)
        powerLock.lock()
        activeTokensCount = max(0, activeTokensCount - 1)
        powerLock.unlock()
    }

    public func isKeepAwakeActive() -> Bool {
        powerLock.lock()
        defer { powerLock.unlock() }
        return activeTokensCount > 0
    }

    // MARK: - Status Snapshot & Active Overrides

    public func activeOverrides() -> ActiveOverrides {
        ActiveOverrides(
            brightness: restoreTracker.hasBrightnessOverride() ? (try? getBuiltinBrightness()) : nil,
            dim: getDimLevel() < 1.0 ? getDimLevel() : nil,
            warmth: getWarmthLevel() > 0.0 ? getWarmthLevel() : nil,
            edrBrightness: restoreTracker.hasEDROverride() ? restoreTracker.appliedEDRBrightness : nil
        )
    }

    public func statusReport() -> StatusReport {
        let sensorsRep = sensors_report()
        let batteryRep = batteryReport()
        let displaysRep = displaysReport()
        let overrides = activeOverrides()
        let keepAwake = isKeepAwakeActive()

        let (score, msg, recs) = HealthScorer.calculateScore(
            sensors: sensorsRep,
            battery: batteryRep,
            activeOverrides: overrides,
            isKeepAwakeActive: keepAwake
        )

        return StatusReport(
            healthScore: score,
            healthScoreMsg: msg,
            recommendations: recs,
            activeOverrides: overrides,
            sensors: sensorsRep,
            battery: batteryRep,
            displays: displaysRep
        )
    }

    // MARK: - Write surface (v0.2 core)

    public func getBuiltinBrightness() throws -> Double {
        try displayWrite.getBuiltinBrightness()
    }

    public func applyBuiltinBrightness(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, config.brightnessMin, config.brightnessMax)
        do {
            let original = try? displayWrite.getBuiltinBrightness()
            if let original { restoreTracker.saveBrightness(Float(original)) }
            try displayWrite.setBuiltinBrightness(Float(clamped))
            logHistory(action: "brightness.set", requested: value, clamped: clamped, applied: clamped, result: "success")
        } catch {
            logHistory(action: "brightness.set", requested: value, clamped: clamped, applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func applyExtendedBrightness(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, config.extendedBrightnessMin, config.extendedBrightnessMax)
        do {
            restoreTracker.saveOriginalEDRHeadroom(edrOverlay)
            restoreTracker.saveEDRBrightness(clamped)
            try displayWrite.applyExtendedBrightness(clamped, displayID: nil)
            logHistory(action: "extbright.set", requested: value, clamped: clamped, applied: clamped, result: "success")
        } catch {
            logHistory(action: "extbright.set", requested: value, clamped: clamped, applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func applyDim(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, config.dimMin, config.dimMax)
        dimOverlay.applyDim(Float(clamped))
        logHistory(action: "dim.set", requested: value, clamped: clamped, applied: clamped, result: "success")
    }

    public func resetDim() {
        dimOverlay.removeAllOverlays()
        logHistory(action: "dim.reset", result: "success")
    }

    public func getDimLevel() -> Double {
        Double(dimOverlay.dimLevel)
    }

    public func getWarmthLevel() -> Double {
        Double(restoreTracker.currentWarmth)
    }

    public func applyWarmth(_ value: Double) throws {
        let clamped = SafetyPolicy.clamp(value, 0.0, 1.0)
        do {
            restoreTracker.saveWarmth(Float(clamped))
            try displayWrite.applyWarmth(Float(clamped))
            logHistory(action: "warmth.set", requested: value, clamped: clamped, applied: clamped, result: "success")
        } catch {
            logHistory(action: "warmth.set", requested: value, clamped: clamped, applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func resetWarmth() throws {
        do {
            try displayWrite.resetWarmth()
            logHistory(action: "warmth.reset", result: "success")
        } catch {
            logHistory(action: "warmth.reset", result: "failed", error: error)
            throw error
        }
    }

    public func restoreAll() {
        restoreTracker.restoreAll()
        logHistory(action: "restore", result: "success")
    }

    // MARK: - Profiles

    public func saveProfile(_ profile: TuneProfile) throws {
        do {
            try profiles.saveProfile(profile)
            logHistory(action: "profile.save", result: "success")
        } catch {
            logHistory(action: "profile.save", result: "failed", error: error)
            throw error
        }
    }

    public func loadProfile(name: String) throws -> TuneProfile {
        try profiles.loadProfile(name: name)
    }

    public func listProfiles() -> [TuneProfile] {
        profiles.listProfiles()
    }

    public func deleteProfile(name: String) throws {
        do {
            try profiles.deleteProfile(name: name)
            logHistory(action: "profile.delete", result: "success")
        } catch {
            logHistory(action: "profile.delete", result: "failed", error: error)
            throw error
        }
    }

    public func applyProfile(_ profile: TuneProfile) throws {
        do {
            if let brightness = profile.brightness {
                try applyBuiltinBrightness(brightness)
            }
            if let dim = profile.dim {
                try applyDim(dim)
            }
            if let warmth = profile.warmth {
                try applyWarmth(warmth)
            }
            logHistory(action: "profile.load", result: "success")
        } catch {
            logHistory(action: "profile.load", result: "failed", error: error)
            throw error
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
        do {
            guard let helper = helperClient else {
                throw TuneError.unsupported(
                    "fan control requires the privileged SMC helper (Pro tier)."
                )
            }
            try helper.setFanFraction(clamped)
            logHistory(action: "fan.set", requested: fraction, clamped: clamped, applied: clamped, result: "success")
        } catch {
            logHistory(action: "fan.set", requested: fraction, clamped: clamped, applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func applyChargeLimit(percent: Int) throws {
        let clamped = SafetyPolicy.clamp(percent, config.chargeLimitMin, config.chargeLimitMax)
        do {
            guard let helper = helperClient else {
                throw TuneError.unsupported(
                    "charge limit requires the privileged SMC helper (Pro tier)."
                )
            }
            try helper.setChargeLimit(clamped)
            logHistory(action: "battery-limit.set", requested: Double(percent), clamped: Double(clamped), applied: Double(clamped), result: "success")
        } catch {
            logHistory(action: "battery-limit.set", requested: Double(percent), clamped: Double(clamped), applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func getHistory() -> [HistoryEvent] {
        historyService.readEvents()
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
