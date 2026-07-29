import SwiftUI
import SymTuneCore

// MARK: - Metrics History Card

/// A card displaying sparkline trends for enabled system metrics.
struct MetricsHistoryCard: View {
    let controller: TuneController
    @ObservedObject var preferencesManager: PreferencesManager
    let metricsReport: SystemMetricsReport?

    var body: some View {
        if let report = metricsReport {
            let ordered = orderedEnabledMetrics()
            let anyEnabled = ordered.contains { metricHasData($0, report: report) }
            if anyEnabled {
                VStack(spacing: 6) {
                    HStack {
                        Text("SYSTEM METRICS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SymairaColors.textMuted)
                        Spacer()
                    }
                    ForEach(ordered, id: \.self) { id in
                        if let stats = controller.metricsHistoryStats(for: id) {
                            metricsRow(id: id, current: stats.current, min: stats.min, max: stats.max)
                        } else if metricHasData(id, report: report) {
                            metricsRowFallback(id: id, report: report)
                        }
                    }
                }
                .padding(12)
                .background(SymairaColors.bgPanel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SymairaColors.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Helpers

    private func orderedEnabledMetrics() -> [MetricIdentifier] {
        let order = preferencesManager.metricOrder
        let enabled = preferencesManager.enabledMetrics
        guard !enabled.isEmpty, !order.isEmpty else { return [] }
        return order.filter { enabled.contains($0) }
    }

    private func metricHasData(_ id: MetricIdentifier, report: SystemMetricsReport) -> Bool {
        switch id {
        case .cpu: return report.cpu.totalUtilization != nil
        case .memory: return report.memory.usedBytes != nil
        case .disk: return report.disk != nil
        case .network: return report.network.aggregateBytesInPerSecond != nil
            || report.network.aggregateBytesOutPerSecond != nil
        default: return false
        }
    }

    private func formatMetricValue(_ id: MetricIdentifier, _ value: Double) -> String {
        switch id {
        case .cpu:
            return String(format: "%.0f%%", value)
        case .memory:
            if value >= 1_073_741_824 {
                return String(format: "%.1f GB", value / 1_073_741_824.0)
            }
            return String(format: "%.0f MB", value / 1_048_576.0)
        case .disk:
            return String(format: "%.0f%%", value)
        case .network:
            return formatNetRateCompact(value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func formatNetRateCompact(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_024.0)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    @ViewBuilder
    private func metricsRow(id: MetricIdentifier, current: Double, min: Double, max: Double) -> some View {
        let samples = controller.metricsHistorySamples(for: id)

        VStack(spacing: 2) {
            HStack {
                Text(id.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SymairaColors.textSecondary)
                Spacer()
                Text(formatMetricValue(id, current))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(SymairaColors.goldSecondary)
            }

            SparklineView(samples: samples, lineColor: SymairaColors.goldPrimary, showAnnotations: true)

            HStack {
                Text("min \(formatMetricValue(id, min))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SymairaColors.textMuted)
                Spacer()
                Text("max \(formatMetricValue(id, max))")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(SymairaColors.textMuted)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func metricsRowFallback(id: MetricIdentifier, report: SystemMetricsReport) -> some View {
        let currentStr: String = {
            switch id {
            case .cpu:
                if let u = report.cpu.totalUtilization {
                    return String(format: "%.0f%%", u * 100)
                }
            case .memory:
                if let b = report.memory.usedBytes {
                    return formatMetricValue(.memory, Double(b))
                }
            case .disk:
                if let d = report.disk, d.capacityBytes > 0 {
                    let pct = Double(d.usedBytes) / Double(d.capacityBytes) * 100
                    return String(format: "%.0f%%", pct)
                }
            case .network:
                let d = report.network.aggregateBytesInPerSecond
                let u = report.network.aggregateBytesOutPerSecond
                if d != nil || u != nil {
                    let total = (d ?? 0) + (u ?? 0)
                    return formatNetRateCompact(total)
                }
            default: break
            }
            return "—"
        }()

        HStack {
            Text(id.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SymairaColors.textSecondary)
            Spacer()
            Text(currentStr)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(SymairaColors.goldSecondary)
            Text("·")
                .font(.system(size: 9))
                .foregroundStyle(SymairaColors.textMuted)
            Text("collecting…")
                .font(.system(size: 9))
                .foregroundStyle(SymairaColors.textMuted)
        }
        .padding(.vertical, 2)
    }
}
