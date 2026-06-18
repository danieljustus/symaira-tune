import Foundation

/// Hardware-safety guardrails. Every write path (brightness, dim, fan, charge
/// limit) MUST route its requested value through this policy before applying.
///
/// Two non-negotiable rules for anything that touches the SMC or display:
///   1. Clamp to a safe range — never pass an unbounded user/agent value to
///      hardware.
///   2. Never disable thermal protection. Fan control may only *raise* the
///      effective floor above the firmware's automatic curve, never silence it.
///
/// The controller is additionally responsible for *restore-on-exit*: any value
/// it overrides during a session is reset to the system default when the
/// process terminates normally.
public enum SafetyPolicy {
    // MARK: Extended / EDR brightness (multiplier over the 100% SDR reference).
    public static let extendedBrightnessMin = 1.0
    public static let extendedBrightnessMax = 1.6

    // MARK: Software dim overlay (1.0 = no dimming, 0.0 = fully black).
    /// Floored above 0 so the agent/user can never blank the screen entirely.
    public static let dimMin = 0.15
    public static let dimMax = 1.0

    // MARK: Built-in hardware brightness (0.0–1.0).
    public static let brightnessMin = 0.0
    public static let brightnessMax = 1.0

    // MARK: Fan speed, expressed as a fraction (0.0–1.0) of the fan's range.
    /// The firmware's automatic curve is always honored as a lower bound; this
    /// fraction can only push the fan *faster*, never below the auto target.
    public static let fanFractionMin = 0.0
    public static let fanFractionMax = 1.0

    // MARK: Battery charge limit (percent).
    public static let chargeLimitMin = 50
    public static let chargeLimitMax = 100

    /// Clamp `value` into the inclusive `[lower, upper]` range.
    public static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
