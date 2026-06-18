import Foundation

/// Thermal/fan sensor reads. v0.1 reports the public, unprivileged thermal
/// pressure level from `ProcessInfo`; detailed die temps and fan RPM come from
/// `SMCService` once the SMC bridge lands (v0.2).
public struct SensorService {
    private let smc: SMCService

    public init(smc: SMCService = SMCService()) {
        self.smc = smc
    }

    public func read() -> SensorReport {
        let temperatures = smc.readTemperatures()
        let fans = smc.readFans()

        var notes: [String] = []
        if !smc.isAvailable {
            notes.append(
                "SMC sensor bridge not yet wired (v0.1). Planned: per-core/GPU die "
                + "temperatures and fan RPM via the AppleSMC IOKit connection (v0.2)."
            )
        }

        return SensorReport(
            thermalPressure: Self.thermalPressureLabel(),
            smcSupported: smc.isAvailable,
            temperatures: temperatures,
            fans: fans,
            notes: notes
        )
    }

    static func thermalPressureLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
