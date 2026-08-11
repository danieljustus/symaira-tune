import Foundation

/// Shared metric formatting.
///
/// The status item and the history card used to carry near-identical copies of
/// these formatters and ran them inside SwiftUI body evaluations. They now live
/// in one place and are called once per refresh.
public enum MetricFormatting {

    // MARK: - Availability

    public static func hasData(_ id: MetricIdentifier, report: SystemMetricsReport) -> Bool {
        switch id {
        case .cpu: return report.cpu.totalUtilization != nil
        case .memory: return report.memory.usedBytes != nil
        case .disk: return report.disk != nil
        case .network:
            return report.network.aggregateBytesInPerSecond != nil
                || report.network.aggregateBytesOutPerSecond != nil
        default: return false
        }
    }

    // MARK: - History card

    /// Format an aggregated history value for the metrics card.
    public static func value(_ id: MetricIdentifier, _ value: Double) -> String {
        switch id {
        case .cpu, .disk:
            return String(format: "%.0f%%", value)
        case .memory:
            if value >= 1_073_741_824 {
                return String(format: "%.1f GB", value / 1_073_741_824.0)
            }
            return String(format: "%.0f MB", value / 1_048_576.0)
        case .network:
            return netRate(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    /// Value shown before enough history exists for min/max, or `nil` when the
    /// metric has no data at all.
    public static func fallbackValue(_ id: MetricIdentifier, report: SystemMetricsReport) -> String? {
        switch id {
        case .cpu:
            guard let utilization = report.cpu.totalUtilization else { return nil }
            return String(format: "%.0f%%", utilization * 100)
        case .memory:
            guard let used = report.memory.usedBytes else { return nil }
            return value(.memory, Double(used))
        case .disk:
            guard let disk = report.disk, disk.capacityBytes > 0 else { return nil }
            return String(format: "%.0f%%", Double(disk.usedBytes) / Double(disk.capacityBytes) * 100)
        case .network:
            let down = report.network.aggregateBytesInPerSecond
            let up = report.network.aggregateBytesOutPerSecond
            guard down != nil || up != nil else { return nil }
            return netRate((down ?? 0) + (up ?? 0))
        default:
            return nil
        }
    }

    /// Human-readable byte size (`"1.8 GB"`, `"482 MB"`, `"96 KB"`).
    /// Shared by the CLI process listing and the popover's process card so both
    /// round the same way.
    public static func bytes(_ value: UInt64) -> String {
        let bytes = Double(value)
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", bytes / 1_073_741_824)
        }
        if bytes >= 1_048_576 {
            return String(format: "%.0f MB", bytes / 1_048_576)
        }
        if bytes >= 1_024 {
            return String(format: "%.0f KB", bytes / 1_024)
        }
        return "\(value) B"
    }

    private static func netRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_024.0)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    // MARK: - Status item

    /// Compact single-line status-item text. Returns `""` when no selected
    /// metric has data, which tells the status item to fall back to its icon.
    public static func statusItemText(
        report: SystemMetricsReport,
        identifiers: [MetricIdentifier]
    ) -> String {
        var parts: [String] = []
        parts.reserveCapacity(identifiers.count)

        for id in identifiers {
            switch id {
            case .cpu:
                if let utilization = report.cpu.totalUtilization {
                    parts.append("CPU \(String(format: "%2d%%", Int(utilization * 100)))")
                }
            case .memory:
                if let used = report.memory.usedBytes {
                    parts.append("RAM \(compactBytes(used))")
                }
            case .disk:
                if let disk = report.disk {
                    let gigabytes = Double(disk.usedBytes) / 1_073_741_824.0
                    parts.append(String(format: "💾%.0fG", gigabytes))
                }
            case .network:
                let down = report.network.aggregateBytesInPerSecond
                let up = report.network.aggregateBytesOutPerSecond
                guard down != nil || up != nil else { continue }
                var text = ""
                if let down { text += "↓\(compactRate(down))" }
                if let up {
                    if !text.isEmpty { text += " " }
                    text += "↑\(compactRate(up))"
                }
                parts.append(text)
            default:
                continue
            }
        }

        return parts.joined(separator: "  ")
    }

    private static func compactBytes(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1fG", Double(bytes) / 1_073_741_824.0)
        }
        return String(format: "%.0fM", Double(bytes) / 1_048_576.0)
    }

    private static func compactRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSecond / 1_048_576.0)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%.0fK", bytesPerSecond / 1_024.0)
        }
        return String(format: "%.0fB", bytesPerSecond)
    }
}
