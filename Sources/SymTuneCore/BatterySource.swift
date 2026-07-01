import Foundation
import IOKit

/// Result of a battery-source read attempt.
public enum BatterySourceResult: Sendable, Equatable {
    /// No AppleSmartBattery node was found (e.g., a desktop Mac).
    case unavailable
    /// The node exists but its properties could not be read.
    case readFailed
    /// Raw properties read successfully from the AppleSmartBattery node.
    case success(BatteryProperties)
}

/// Raw battery properties extracted from the AppleSmartBattery IORegistry node.
/// Values are optional because individual keys can be absent on some models.
public struct BatteryProperties: Sendable, Equatable {
    public let isCharging: Bool?
    public let externalConnected: Bool?
    public let designCapacity: Int?
    public let rawMaxCapacity: Int?
    public let rawCurrentCapacity: Int?
    public let cycleCount: Int?
    /// Temperature in centidegrees (divide by 100.0 for Celsius).
    public let temperatureCentidegrees: Int?

    public init(
        isCharging: Bool? = nil,
        externalConnected: Bool? = nil,
        designCapacity: Int? = nil,
        rawMaxCapacity: Int? = nil,
        rawCurrentCapacity: Int? = nil,
        cycleCount: Int? = nil,
        temperatureCentidegrees: Int? = nil
    ) {
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.designCapacity = designCapacity
        self.rawMaxCapacity = rawMaxCapacity
        self.rawCurrentCapacity = rawCurrentCapacity
        self.cycleCount = cycleCount
        self.temperatureCentidegrees = temperatureCentidegrees
    }
}

/// Abstracts the low-level AppleSmartBattery IORegistry read so `BatteryService`
/// can be unit-tested without real hardware.
public protocol BatterySource: Sendable {
    func readProperties() -> BatterySourceResult
}

/// Production battery source that reads from the `AppleSmartBattery` IORegistry node.
public struct HardwareBatterySource: BatterySource, Sendable {
    public init() {}

    public func readProperties() -> BatterySourceResult {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            return .unavailable
        }
        defer { IOObjectRelease(service) }

        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let props = unmanagedProps?.takeRetainedValue() as? [String: Any]
        else {
            return .readFailed
        }

        return .success(BatteryProperties(
            isCharging: props["IsCharging"] as? Bool,
            externalConnected: props["ExternalConnected"] as? Bool,
            designCapacity: props["DesignCapacity"] as? Int,
            rawMaxCapacity: (props["AppleRawMaxCapacity"] as? Int) ?? (props["MaxCapacity"] as? Int),
            rawCurrentCapacity: (props["AppleRawCurrentCapacity"] as? Int) ?? (props["CurrentCapacity"] as? Int),
            cycleCount: props["CycleCount"] as? Int,
            temperatureCentidegrees: props["Temperature"] as? Int
        ))
    }
}
