import Foundation

/// Facade over the individual services. Both the CLI and the MCP server talk to
/// the controller only — they never touch services directly. This is also where
/// the safety policy and restore-on-exit bookkeeping live.
public final class TuneController: Sendable {
    private let smc: SMCService
    private let sensors: SensorService
    private let battery: BatteryService
    private let displays = DisplayService()
    private let power = PowerService()
    private let dimOverlay = DimOverlay()
    private let edrOverlay = EDROverlayService()
    private let displayWrite: any DisplayWriteServiceProtocol
    private let profiles: ProfileService
    public let config: TuneConfig
    private let restoreTracker: OverrideTracker
    private let fanControl: FanControlService
    private let chargeLimit: ChargeLimitService
    private let smcRestoreTracker: SMCRestoreTracker
    nonisolated(unsafe) private var helperClient: (any SMCHelperProtocol)?

    public let dataDir: URL
    private let historyService: HistoryService
    private let powerLock = NSLock()
    nonisolated(unsafe) private var activeTokensCount = 0

    public init(
        config: TuneConfig = TuneConfig(),
        displayWrite: (any DisplayWriteServiceProtocol)? = nil,
        smcService: SMCService? = nil,
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
        let smc = smcService ?? SMCService()
        self.smc = smc
        self.sensors = SensorService(smc: smc)
        self.fanControl = FanControlService(smc: smc, sensors: sensors)
        self.chargeLimit = ChargeLimitService(smc: smc)
        self.battery = BatteryService(isChargeLimitSupported: { [chargeLimit] in
            chargeLimit.detectKeyFamily() != nil
        })
        self.smcRestoreTracker = SMCRestoreTracker(smc: smc, fanControl: fanControl, chargeLimit: chargeLimit)
        self.restoreTracker = OverrideTracker(
            displayService: displays,
            edrOverlay: edrOverlay,
            onRestore: { [smcRestoreTracker] in smcRestoreTracker.restoreAll() }
        )
        restoreTracker.registerSignalHandlers()
    }

    deinit {
        restoreTracker.restoreAll()
        smcRestoreTracker.restoreAll()
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
        let smcWritable = smc.isAvailable
        return PermissionStatus(
            privilegedHelperInstalled: smcWritable,
            notes: [
                smcWritable
                    ? "SMC write access available. Fan and charge-limit writes require root (run with sudo)."
                    : "SMC write access unavailable. Fan and charge-limit features require a real Mac and root privileges.",
            ]
        )
    }

    public func capabilities() -> CapabilityReport {
        let batteryPresent = battery.read().present
        let edrCapable = displays.anyEDRCapable()
        let smcAvailable = sensors.smcAvailable
        let smcWritable = smc.isAvailable

        let caps: [Capability] = [
            Capability(id: "sensors.thermalPressure", available: true, tier: "core",
                       detail: "Coarse thermal pressure from ProcessInfo (nominal…critical)."),
            Capability(id: "sensors.smc", available: smcAvailable, tier: "core",
                       detail: smcAvailable
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
            Capability(id: "fan.control", available: smcWritable, tier: "core",
                       detail: smcWritable
                            ? "Fan speed control via SMC. Requires root for writes."
                            : "SMC unavailable — fan control not possible."),
            Capability(id: "battery.chargeLimit", available: smcWritable, tier: "core",
                       detail: smcWritable
                            ? "Battery charge limiting via SMC. Requires root for writes."
                            : "SMC unavailable — charge limiting not possible."),
        ]

        var recommendations: [String] = []
        if !edrCapable {
            recommendations.append("No EDR-capable display detected; extended brightness will be unavailable here.")
        }
        if !batteryPresent {
            recommendations.append("No battery detected; battery features are not applicable on this Mac.")
        }
        if recommendations.isEmpty {
            recommendations.append("Core features are ready. Run `symtune serve` to expose them over MCP.")
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
            edrBrightness: restoreTracker.hasEDROverride() ? restoreTracker.appliedEDRBrightness : nil,
            fanFraction: activeFanFraction(),
            chargeLimitPercent: activeChargeLimitPercent()
        )
    }

    private func activeFanFraction() -> Double? {
        // Best-effort: read current fan targets and report the uniform fraction.
        guard smc.isAvailable else { return nil }
        let fanCount = smc.readKeyUInt("FNum").map { Int($0) } ?? 0
        guard fanCount > 0 else { return nil }
        var fractions: [Double] = []
        for i in 0..<fanCount {
            guard let mode = smc.readFanMode(fanIndex: i), mode == 1 else { return nil }
            guard let target = smc.readFanTargetRPM(fanIndex: i),
                  let max = smc.readFanMaxRPM(fanIndex: i), max > 0 else { return nil }
            fractions.append(target / max)
        }
        let avg = fractions.reduce(0, +) / Double(fractions.count)
        return avg
    }

    private func activeChargeLimitPercent() -> Int? {
        guard smc.isAvailable, let family = chargeLimit.detectKeyFamily() else { return nil }
        switch family {
        case .chte:
            return smc.readKeyUInt32("CHTE").map { $0 == 1 ? 80 : nil } ?? nil
        case .ch0b:
            return smc.readKeyUInt("CH0B").map { $0 == 2 ? 80 : nil } ?? nil
        case .chlc:
            return smc.readKeyUInt("CHLC").map { Int($0) }
        }
    }

    public func statusReport() -> StatusReport {
        let sensorsRep = sensors_report()
        let batteryRep = batteryReport()
        let displaysRep = displaysReport()
        let overrides = activeOverrides()
        let keepAwake = isKeepAwakeActive()

        let result = HealthScorer.calculateScore(
            sensors: sensorsRep,
            battery: batteryRep,
            activeOverrides: overrides,
            isKeepAwakeActive: keepAwake
        )

        return StatusReport(
            healthScore: result.score,
            healthScoreMsg: result.message,
            recommendations: result.recommendations,
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
        smcRestoreTracker.restoreAll()
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

    // MARK: - Fan and charge control

    public func applyFan(fraction: Double) throws {
        let clamped = SMCWritePolicy.clampFanFraction(fraction, min: config.fanFractionMin, max: config.fanFractionMax)
        do {
            let fanCount = smc.readKeyUInt("FNum").map { Int($0) } ?? 0
            for i in 0..<fanCount {
                smcRestoreTracker.saveFanOriginal(fanIndex: i)
            }
            try fanControl.applyFan(fraction: fraction, config: config)
            logHistory(action: "fan.set", requested: fraction, clamped: clamped, applied: clamped, result: "success")
        } catch let error as FanControlError {
            logHistory(action: "fan.set", requested: fraction, clamped: clamped, applied: nil, result: "failed", error: error)
            throw mapFanControlError(error)
        } catch let error as SMCWritePolicy.ValidationError {
            logHistory(action: "fan.set", requested: fraction, clamped: clamped, applied: nil, result: "failed", error: error)
            throw mapValidationError(error)
        } catch {
            logHistory(action: "fan.set", requested: fraction, clamped: clamped, applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func restoreFanAuto() throws {
        do {
            try fanControl.restoreAuto()
            logHistory(action: "fan.auto", result: "success")
        } catch let error as FanControlError {
            logHistory(action: "fan.auto", result: "failed", error: error)
            throw mapFanControlError(error)
        } catch {
            logHistory(action: "fan.auto", result: "failed", error: error)
            throw error
        }
    }

    public func applyChargeLimit(percent: Int) throws {
        let clamped = SafetyPolicy.clamp(percent, config.chargeLimitMin, config.chargeLimitMax)
        do {
            try SMCWritePolicy.requireACPower(battery: battery)
            smcRestoreTracker.saveChargeOriginal()
            try chargeLimit.applyChargeLimit(percent: percent, config: config)
            logHistory(action: "battery-limit.set", requested: Double(percent), clamped: Double(clamped), applied: Double(clamped), result: "success")
        } catch let error as SMCWritePolicy.ValidationError {
            logHistory(action: "battery-limit.set", requested: Double(percent), clamped: Double(clamped), applied: nil, result: "failed", error: error)
            throw mapValidationError(error)
        } catch {
            logHistory(action: "battery-limit.set", requested: Double(percent), clamped: Double(clamped), applied: nil, result: "failed", error: error)
            throw error
        }
    }

    public func clearChargeLimit() throws {
        do {
            try chargeLimit.clearChargeLimit()
            logHistory(action: "battery-limit.clear", result: "success")
        } catch {
            logHistory(action: "battery-limit.clear", result: "failed", error: error)
            throw error
        }
    }

    public func getHistory() -> [HistoryEvent] {
        historyService.readEvents()
    }

    private func mapFanControlError(_ error: FanControlError) -> TuneError {
        switch error {
        case .noFansDetected:
            return .unsupported("SMC reports no fans; fan control is unavailable")
        case .fanModeWriteRejected(let index):
            return .permission("SMC rejected manual mode for fan \(index); run with sudo")
        case .targetRPMWriteFailed(let index):
            return .permission("SMC rejected target RPM for fan \(index)")
        case .unsupportedPlatform:
            return .unsupported("Fan control is not supported on this platform")
        }
    }

    private func mapValidationError(_ error: SMCWritePolicy.ValidationError) -> TuneError {
        switch error {
        case .noSMCConnection:
            return .permission("SMC not available for write")
        case .thermalEmergency(let celsius):
            return .permission("thermal emergency at \(celsius)°C; refusing write")
        case .fanMaxRPMUnavailable(let index):
            return .unsupported("SMC did not report maximum RPM for fan \(index)")
        case .chargeLimitNoACPower:
            return .permission("charge limit requires AC power and SMC write access")
        }
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
