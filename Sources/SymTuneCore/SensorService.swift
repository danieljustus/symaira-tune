import Foundation

/// Thermal/fan sensor reads. Reports the public, unprivileged thermal
/// pressure level from `ProcessInfo` plus detailed die temps and fan RPM
/// from the SMC bridge (`SMCService`). The SMC read path is unprivileged
/// (user type 0) — no root required.
public struct SensorService: Sendable {
    private let smc: SMCService

    public init(smc: SMCService = SMCService()) {
        self.smc = smc
    }

    public var smcAvailable: Bool { smc.isAvailable }

    public func read() -> SensorReport {
        let temperatures = smc.readTemperatures()
        let fans = smc.readFans()

        var notes: [String] = []
        if !smc.isAvailable {
            notes.append(
                "SMC connection failed — detailed die temperatures and fan RPM "
                + "are unavailable. Ensure you are running on a real Mac (not a VM)."
            )
        } else {
            if temperatures.isEmpty {
                notes.append(
                    "SMC connected but no temperature sensors returned data. "
                    + "Your Mac may use keys not yet in the probe list."
                )
            }
            if fans.isEmpty {
                notes.append(
                    "No fans detected (fanless Mac or SMC returned fan count 0)."
                )
            }
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
