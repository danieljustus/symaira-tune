import Foundation
import IOKit.pwr_mgt

/// Opaque handle for an active keep-awake power assertion. Release it via
/// `PowerService.end(_:)` (or let the process exit — macOS releases assertions
/// held by a terminated process automatically).
public struct KeepAwakeToken: Sendable {
    let id: IOPMAssertionID
}

/// Wraps IOKit power-management assertions to prevent idle sleep. Fully
/// unprivileged — the analog of `/usr/bin/caffeinate`.
public struct PowerService: Sendable {
    public init() {}

    public func begin(reason: String, preventDisplaySleep: Bool) throws -> KeepAwakeToken {
        var id: IOPMAssertionID = IOPMAssertionID(0)
        let type = preventDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            throw TuneError.failed("Failed to create power assertion (IOReturn \(result)).")
        }
        return KeepAwakeToken(id: id)
    }

    public func end(_ token: KeepAwakeToken) {
        IOPMAssertionRelease(token.id)
    }
}
