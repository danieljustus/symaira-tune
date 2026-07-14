import Foundation

/// Tracks original SMC values for fan and charge-limit overrides so they can
/// be restored when the process exits or receives SIGINT/SIGTERM.
///
/// This is the SMC counterpart to `OverrideTracker` (which handles display
/// overrides). The controller is responsible for calling `restoreAll()` on
/// teardown and from its signal handlers.
final class SMCRestoreTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var fanOriginals: [Int: (mode: UInt8, targetRPM: Double)] = [:]
    private var originalFSBitmask: UInt?
    private var originalChargeInhibit: Bool?
    private var activeChargeKeyFamily: ChargeLimitKeyFamily?
    private var hasOverrides = false

    private let smc: SMCService
    private let fanControl: FanControlService
    private let chargeLimit: ChargeLimitService

    init(smc: SMCService, fanControl: FanControlService, chargeLimit: ChargeLimitService) {
        self.smc = smc
        self.fanControl = fanControl
        self.chargeLimit = chargeLimit
    }

    // MARK: - Fan tracking

    /// Save the original fan mode and target RPM before the first override.
    func saveFanOriginal(fanIndex: Int) {
        guard smc.isAvailable else { return }
        lock.lock()
        defer { lock.unlock() }
        guard fanOriginals[fanIndex] == nil else { return }
        guard let state = fanControl.originalState(fanIndex: fanIndex) else { return }
        if let mode = state.mode {
            fanOriginals[fanIndex] = (mode, state.targetRPM ?? 0)
            hasOverrides = true
        }
        #if arch(x86_64)
        if originalFSBitmask == nil {
            originalFSBitmask = FanControlService.originalFSBitmask(smc: smc)
        }
        #endif
    }

    // MARK: - Charge tracking

    /// Save the original charge inhibit state before the first override.
    func saveChargeOriginal() {
        guard smc.isAvailable else { return }
        lock.lock()
        defer { lock.unlock() }
        guard originalChargeInhibit == nil else { return }
        guard let family = chargeLimit.detectKeyFamily() else { return }
        activeChargeKeyFamily = family
        switch family {
        case .chte, .ch0b:
            originalChargeInhibit = chargeLimit.readInhibitState() ?? false
        case .chlc:
            originalChargeInhibit = smc.readKeyUInt("CHLC") == 100
        }
        hasOverrides = true
    }

    // MARK: - Restore

    func restoreAll() {
        lock.lock()
        let fanOriginalsCopy = fanOriginals
        let fsCopy = originalFSBitmask
        let chargeInhibit = originalChargeInhibit
        let chargeFamily = activeChargeKeyFamily
        fanOriginals.removeAll()
        originalFSBitmask = nil
        originalChargeInhibit = nil
        activeChargeKeyFamily = nil
        hasOverrides = false
        lock.unlock()

        guard smc.isAvailable else { return }
        restoreFans(fanOriginalsCopy, fsCopy)
        restoreCharge(chargeInhibit, chargeFamily)
    }

    private func restoreFans(
        _ originals: [Int: (mode: UInt8, targetRPM: Double)],
        _ originalFS: UInt?
    ) {
        #if arch(arm64)
        for (index, original) in originals.sorted(by: { $0.key < $1.key }) {
            _ = smc.writeKeyValue("F\(index)Md", value: Double(original.mode), dataType: "ui8 ")
            if original.mode == 1 {
                _ = smc.writeKeyValue("F\(index)Tg", value: original.targetRPM, dataType: "flt ")
            }
        }
        if !originals.isEmpty {
            _ = smc.writeKeyValue("Ftst", value: 0, dataType: "ui8 ")
        }
        #else
        if !originals.isEmpty {
            let fs = originalFS ?? 0
            _ = smc.writeKeyValue("FS!", value: Double(fs), dataType: "ui16")
            for (index, original) in originals.sorted(by: { $0.key < $1.key }) {
                if original.mode == 1 {
                    _ = smc.writeKeyValue("F\(index)Tg", value: original.targetRPM, dataType: "fpe2")
                }
            }
        }
        #endif
    }

    private func restoreCharge(_ originalInhibit: Bool?, _ family: ChargeLimitKeyFamily?) {
        guard let originalInhibit, let family else { return }
        switch family {
        case .chte:
            _ = smc.writeKeyValue("CHTE", value: originalInhibit ? 1 : 0, dataType: "ui32")
        case .ch0b:
            _ = smc.writeKeyValue("CH0B", value: originalInhibit ? 2 : 0, dataType: "ui8 ")
            _ = smc.writeKeyValue("CH0C", value: originalInhibit ? 2 : 0, dataType: "ui8 ")
        case .chlc:
            _ = smc.writeKeyValue("CHLC", value: originalInhibit ? 100 : 0, dataType: "ui16")
        }
    }

    deinit {
        restoreAll()
    }
}
