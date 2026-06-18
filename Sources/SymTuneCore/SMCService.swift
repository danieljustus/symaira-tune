import Foundation

/// Bridge to the System Management Controller (SMC) for temperature/fan sensors
/// and — in the Pro tier — fan writes.
///
/// STATUS (v0.1): stub. A full SMC bridge (AppleSMC IOKit connection, key
/// decoding à la smcFanControl / Macs Fan Control) is planned for v0.2 (reads)
/// and the Pro helper (writes). Reads are unprivileged; writes require the
/// privileged helper. See docs/roadmap.md and docs/commercial-boundary.md.
public struct SMCService {
    public init() {}

    /// Whether the SMC bridge is wired and a connection is available.
    public var isAvailable: Bool { false }

    public func readTemperatures() -> [SensorReading] { [] }

    public func readFans() -> [FanReading] { [] }
}
