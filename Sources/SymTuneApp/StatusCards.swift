import SwiftUI
import SymTuneCore

// MARK: - Shared card chrome

/// The popover's density knobs, in one place.
///
/// The panel is a glance-and-adjust surface, not a document: every card is
/// visible at once, so padding spent per card is paid eight times over in
/// total height. Tune these rather than sprinkling literals through the cards.
enum CardMetrics {
    /// Padding inside a card, between its border and its content.
    static let cardPadding: CGFloat = 10
    /// Gap between two cards in the popover stack.
    static let stackSpacing: CGFloat = 10
    /// Padding between the popover edge and the card stack.
    static let panelPadding: CGFloat = 12
    /// Gap between rows inside one card.
    static let rowSpacing: CGFloat = 8
    /// Extra vertical breathing room around an individual readout row.
    static let rowPadding: CGFloat = 2
}

/// The panel background shared by every card in the status popover.
struct CardStyle: ViewModifier {
    var borderColor: Color = SymairaColors.border

    func body(content: Content) -> some View {
        content
            .padding(CardMetrics.cardPadding)
            .background(SymairaColors.bgPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle(borderColor: Color = SymairaColors.border) -> some View {
        modifier(CardStyle(borderColor: borderColor))
    }
}

// MARK: - Header / footer

struct StatusHeaderView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SYMAIRA TUNE")
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundStyle(SymairaColors.goldPrimary)
                Text("v\(TuneVersion.current)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SymairaColors.textMuted)
            }
            Spacer()
            Circle()
                .fill(SymairaColors.success.opacity(0.8))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 4)
    }
}

struct StatusFooterView: View {
    let openPreferences: () -> Void

    var body: some View {
        HStack {
            Button(action: openPreferences) {
                Text("Preferences\u{2026}")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(SymairaColors.bgPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SymairaColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SymairaColors.bgDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(SymairaColors.goldPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

// MARK: - System status

/// Battery and thermal readout.
///
/// `Equatable` on the two reports: while neither changes — which is most
/// refreshes — SwiftUI skips this subtree entirely.
struct SystemStatusCard: View, Equatable {
    let battery: BatteryReport?
    let sensors: SensorReport?

    var body: some View {
        VStack(spacing: CardMetrics.rowSpacing - 2) {
            HStack {
                Text("SYSTEM STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SymairaColors.textMuted)
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: batteryIcon)
                    .foregroundStyle(SymairaColors.goldPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(batteryState)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SymairaColors.textPrimary)
                    Text(batteryDetails)
                        .font(.system(size: 9))
                        .foregroundStyle(SymairaColors.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, CardMetrics.rowPadding)

            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(SymairaColors.goldPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Thermal:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SymairaColors.textPrimary)
                        Text(sensors?.thermalPressure ?? "nominal")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(thermalColor)
                    }
                    if let details = sensorDetails {
                        Text(details)
                            .font(.system(size: 9))
                            .foregroundStyle(SymairaColors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, CardMetrics.rowPadding)
        }
        .cardStyle()
    }

    // MARK: Derived text

    private var batteryIcon: String {
        guard let battery, battery.present else { return "battery.0" }
        if battery.charging == true { return "battery.100.bolt" }
        guard let percent = battery.currentCapacityPercent else { return "battery.50" }
        if percent > 80 { return "battery.100" }
        if percent > 50 { return "battery.75" }
        if percent > 25 { return "battery.50" }
        return "battery.25"
    }

    private var batteryState: String {
        guard let battery, battery.present else { return "No Battery Detected" }
        let capacity = battery.currentCapacityPercent.map { "\($0)%" } ?? "Unknown"
        let state = battery.charging == true ? "Charging" : "On Battery"
        return "\(capacity) (\(state))"
    }

    private var batteryDetails: String {
        guard let battery, battery.present else { return "Desktop Mac" }
        let health = battery.healthPercent.map { "\($0)% Health" } ?? ""
        let cycles = battery.cycleCount.map { "\($0) Cycles" } ?? ""
        let separator = !health.isEmpty && !cycles.isEmpty ? " · " : ""
        return "\(health)\(separator)\(cycles)"
    }

    private var thermalColor: Color {
        switch (sensors?.thermalPressure ?? "nominal").lowercased() {
        case "nominal": return SymairaColors.success
        case "fair": return SymairaColors.warning
        default: return SymairaColors.danger
        }
    }

    private var sensorDetails: String? {
        guard let sensors, !sensors.temperatures.isEmpty || !sensors.fans.isEmpty else {
            // Two different situations, previously reported with one (wrong)
            // sandbox message: the SMC never answered at all, or it answered
            // but reports no sensors this Mac exposes to us.
            guard let sensors else { return nil }
            return sensors.smcSupported
                ? "No detailed sensors reported"
                : "SMC unavailable on this macOS build"
        }
        var parts: [String] = []
        if let cpu = sensors.temperatures.first(where: { $0.label.contains("CPU") }) {
            parts.append(String(format: "CPU: %.1f°C", cpu.celsius))
        }
        if let fan = sensors.fans.first {
            parts.append("Fan: \(fan.rpm) RPM")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Connected displays

/// The attached-display list. Changes only when a monitor is plugged in, so
/// `Equatable` keeps it out of every other refresh.
struct DisplaysCard: View, Equatable {
    let displays: [DisplayInfo]

    var body: some View {
        VStack(spacing: CardMetrics.rowPadding + 3) {
            HStack {
                Text("CONNECTED DISPLAYS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SymairaColors.textMuted)
                Spacer()
            }

            if displays.isEmpty {
                Text("No active displays found")
                    .font(.system(size: 11))
                    .foregroundStyle(SymairaColors.textSecondary)
            } else {
                ForEach(displays, id: \.displayID) { display in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(display.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SymairaColors.textPrimary)
                            Text(display.isBuiltin == true ? "Built-in Display" : "External Display")
                                .font(.system(size: 9))
                                .foregroundStyle(SymairaColors.textSecondary)
                        }
                        Spacer()
                        if display.edrCapable {
                            Text("EDR \(String(format: "%.1f", display.maxEDRHeadroom))x")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SymairaColors.goldPrimary.opacity(0.12))
                                .foregroundStyle(SymairaColors.goldPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.vertical, CardMetrics.rowPadding)
                }
            }
        }
        .cardStyle()
    }
}
