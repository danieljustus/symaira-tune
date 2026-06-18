import Foundation

/// Battery charge limit service. Provides logic for setting/clearing charge
/// limits via the privileged SMC helper. Handles Intel vs Apple Silicon
/// SMC key differences and enforces SafetyPolicy clamp ranges.
///
/// The actual SMC writes go through `SMCHelperProtocol`. This service
/// provides the configuration and validation layer.
public struct BatteryLimitService: Sendable {
    public init() {}

    /// SMC keys for battery charge limiting.
    /// Apple Silicon uses `CHLC` (Charge Level Config), Intel uses `B0CT`
    /// (Battery 0 Charge Target) or similar.
    public enum SMCChargeKey: Sendable {
        case appleSilicon
        case intel

        /// The 4-character SMC key for this platform.
        public var key: String {
            switch self {
            case .appleSilicon: return "CHLC"
            case .intel: return "B0CT"
            }
        }

        /// Detect the appropriate key for the current platform.
        public static var current: SMCChargeKey {
            #if arch(arm64)
            return .appleSilicon
            #else
            return .intel
            #endif
        }
    }

    /// Validate and clamp a charge limit percent.
    public func validatePercent(_ percent: Int) -> Int {
        SafetyPolicy.clamp(percent, SafetyPolicy.chargeLimitMin, SafetyPolicy.chargeLimitMax)
    }

    /// Description of what the charge limit operation does.
    public func describeOperation(percent: Int) -> String {
        let clamped = validatePercent(percent)
        return "Set battery charge limit to \(clamped)% via \(SMCChargeKey.current.key) SMC key"
    }
}
