import Foundation
import IOKit

/// Reads battery health from the IORegistry `AppleSmartBattery` node. Fully
/// unprivileged and works on Intel and Apple Silicon notebooks. Returns
/// `present: false` on desktops (no such node).
///
/// Raw `AppleSmartBattery` keys vary slightly across Mac models; values are
/// reported best-effort with an explanatory note.
public struct BatteryService {
    public init() {}

    public func read() -> BatteryReport {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            return BatteryReport(
                present: false, charging: nil, externalConnected: nil,
                currentCapacityPercent: nil, cycleCount: nil,
                designCapacityMah: nil, maxCapacityMah: nil, healthPercent: nil,
                temperatureCelsius: nil, chargeLimitSupported: false,
                notes: ["No AppleSmartBattery node — likely a desktop Mac."]
            )
        }
        defer { IOObjectRelease(service) }

        var unmanagedProps: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(service, &unmanagedProps, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let props = unmanagedProps?.takeRetainedValue() as? [String: Any]
        else {
            return BatteryReport(
                present: true, charging: nil, externalConnected: nil,
                currentCapacityPercent: nil, cycleCount: nil,
                designCapacityMah: nil, maxCapacityMah: nil, healthPercent: nil,
                temperatureCelsius: nil, chargeLimitSupported: false,
                notes: ["Failed to read AppleSmartBattery properties."]
            )
        }

        let design = props["DesignCapacity"] as? Int
        let rawMax = (props["AppleRawMaxCapacity"] as? Int) ?? (props["MaxCapacity"] as? Int)
        let rawCurrent = (props["AppleRawCurrentCapacity"] as? Int) ?? (props["CurrentCapacity"] as? Int)

        var health: Int?
        if let design, design > 0, let rawMax {
            health = Int((Double(rawMax) / Double(design) * 100).rounded())
        }

        var percent: Int?
        if let rawMax, rawMax > 0, let rawCurrent {
            percent = SafetyPolicy.clamp(Int((Double(rawCurrent) / Double(rawMax) * 100).rounded()), 0, 100)
        }

        var temperatureC: Double?
        if let raw = props["Temperature"] as? Int {
            temperatureC = Double(raw) / 100.0
        }

        return BatteryReport(
            present: true,
            charging: props["IsCharging"] as? Bool,
            externalConnected: props["ExternalConnected"] as? Bool,
            currentCapacityPercent: percent,
            cycleCount: props["CycleCount"] as? Int,
            designCapacityMah: design,
            maxCapacityMah: rawMax,
            healthPercent: health,
            temperatureCelsius: temperatureC,
            chargeLimitSupported: false,
            notes: [
                "Read from raw AppleSmartBattery keys; interpretation can vary by Mac model.",
                "Setting a charge limit requires the privileged Pro helper (not in v0.1).",
            ]
        )
    }
}
