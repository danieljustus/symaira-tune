import SwiftUI
import Combine
import SymTuneCore
import SymairaUpdateCheck

@MainActor
struct MainStatusView: View {
    let controller: TuneController
    @ObservedObject var updateChecker: AppUpdateChecker

    // Sliders state
    @State private var brightness: Double = 0.5
    @State private var dim: Double = 0.0
    @State private var warmth: Double = 0.0
    @State private var extendedBrightness: Double = 1.0
    @State private var fanFraction: Double = 0.0
    @State private var isFanManualMode: Bool = false
    @State private var fanError: String?

    // Stats state
    @State private var batteryReport: BatteryReport?
    @State private var sensorReport: SensorReport?
    @State private var displayReport: DisplaysReport?

    // Timer for periodic updates
    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            // Header
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
                // Indicator
                Circle()
                    .fill(SymairaColors.success.opacity(0.8))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 4)

            Divider()
                .background(SymairaColors.goldPrimary.opacity(0.15))

            // Display Controls Card
            VStack(spacing: 12) {
                // Brightness
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Screen Brightness", systemImage: "sun.max.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SymairaColors.textSecondary)
                        Spacer()
                        Text("\(Int(brightness * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(SymairaColors.goldSecondary)
                    }
                    Slider(value: $brightness, in: 0.0...1.0) { _ in
                        try? controller.applyBuiltinBrightness(brightness)
                    }
                    .tint(SymairaColors.goldPrimary)
                }

                // Dim
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Software Dimming", systemImage: "moon.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SymairaColors.textSecondary)
                        Spacer()
                        Text("\(Int(dim * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(SymairaColors.goldSecondary)
                    }
                    Slider(value: $dim, in: 0.0...0.85) { _ in
                        try? controller.applyDim(dim)
                    }
                    .tint(SymairaColors.goldPrimary)
                }

                // Warmth
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Color Warmth", systemImage: "thermometer.sun.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SymairaColors.textSecondary)
                        Spacer()
                        Text("\(Int(warmth * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(SymairaColors.goldSecondary)
                    }
                    Slider(value: $warmth, in: 0.0...1.0) { _ in
                        try? controller.applyWarmth(warmth)
                    }
                    .tint(SymairaColors.goldPrimary)
                }

                // Extended Brightness
                if isEDRCapable {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Extended Brightness", systemImage: "sun.max.trianglebadge.exclamationmark.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SymairaColors.textSecondary)
                            Spacer()
                            Text("\(Int(extendedBrightness * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(SymairaColors.goldSecondary)
                        }
                        Slider(value: $extendedBrightness, in: 1.0...1.6) { _ in
                            try? controller.applyExtendedBrightness(extendedBrightness)
                        }
                        .tint(SymairaColors.goldPrimary)
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

            // Fan Control Card
            VStack(spacing: 12) {
                HStack {
                    Label("Fan Control", systemImage: "fanblades.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SymairaColors.textSecondary)
                    Spacer()
                    Toggle("", isOn: manualFanBinding)
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Target Speed")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isFanManualMode ? SymairaColors.textSecondary : SymairaColors.textMuted)
                        Spacer()
                        Text("\(Int(fanFraction * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(isFanManualMode ? SymairaColors.goldSecondary : SymairaColors.textMuted)
                    }
                    Slider(value: $fanFraction, in: 0.0...1.0) { _ in
                        do {
                            try controller.applyFan(fraction: fanFraction)
                            fanError = nil
                        } catch {
                            fanError = error.localizedDescription
                        }
                    }
                    .tint(SymairaColors.goldPrimary)
                    .disabled(!isFanManualMode)
                }

                if let errorMsg = fanError {
                    Text(errorMsg)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SymairaColors.danger)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .background(SymairaColors.bgPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SymairaColors.border, lineWidth: 1)
            )

            // System Status Card
            VStack(spacing: 8) {
                HStack {
                    Text("SYSTEM STATUS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SymairaColors.textMuted)
                    Spacer()
                }

                // Battery Readout
                HStack(spacing: 8) {
                    Image(systemName: getBatteryIcon())
                        .foregroundStyle(SymairaColors.goldPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(getBatteryStateText())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SymairaColors.textPrimary)
                        Text(getBatteryDetailsText())
                            .font(.system(size: 9))
                            .foregroundStyle(SymairaColors.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                // Thermal & Sensors Readout
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundStyle(SymairaColors.goldPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text("Thermal:")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SymairaColors.textPrimary)
                            Text(sensorReport?.thermalPressure ?? "nominal")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(getThermalColor())
                        }
                        if let text = getSensorDetailsText() {
                            Text(text)
                                .font(.system(size: 9))
                                .foregroundStyle(SymairaColors.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .padding(12)
            .background(SymairaColors.bgPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SymairaColors.border, lineWidth: 1)
            )

            // Update Notification Card
            if case .available(let release) = updateChecker.status {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(SymairaColors.goldPrimary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Update Available")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SymairaColors.goldPrimary)
                            Text(release.tagName)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(SymairaColors.textSecondary)
                        }
                        Spacer()
                        Button("Download") {
                            if let url = URL(string: release.htmlURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(SymairaColors.goldPrimary)
                        .controlSize(.small)

                        Button("Skip") {
                            updateChecker.skip(release)
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                        .foregroundStyle(SymairaColors.textMuted)
                    }
                }
                .padding(12)
                .background(SymairaColors.bgPanel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SymairaColors.borderStrong, lineWidth: 1)
                )
            }

            // Connected Displays Card
            VStack(spacing: 6) {
                HStack {
                    Text("CONNECTED DISPLAYS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SymairaColors.textMuted)
                    Spacer()
                }

                if let displays = displayReport?.displays, !displays.isEmpty {
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
                        .padding(.vertical, 3)
                    }
                } else {
                    Text("No active displays found")
                        .font(.system(size: 11))
                        .foregroundStyle(SymairaColors.textSecondary)
                }
            }
            .padding(12)
            .background(SymairaColors.bgPanel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SymairaColors.border, lineWidth: 1)
            )

            // Footer
            HStack {
                Spacer()
                Button(
                    action: {
                        NSApp.terminate(nil)
                    },
                    label: {
                        Text("Quit")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SymairaColors.bgDark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(SymairaColors.goldPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                )
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 320)
        .background(SymairaColors.bgDark)
        .onAppear {
            refreshData()
        }
        .onReceive(timer) { _ in
            refreshData()
        }
    }

    // MARK: - Helpers

    private func refreshData() {
        // Read initial controls state
        if let currentBrightness = try? controller.getBuiltinBrightness() {
            self.brightness = currentBrightness
        }
        self.dim = controller.getDimLevel()
        self.warmth = controller.getWarmthLevel()

        let overrides = controller.activeOverrides()
        if let activeEDR = overrides.edrBrightness {
            self.extendedBrightness = activeEDR
        } else {
            self.extendedBrightness = 1.0
        }

        if let activeFan = overrides.fanFraction {
            self.fanFraction = activeFan
            self.isFanManualMode = true
        } else {
            self.isFanManualMode = false
        }

        // Read sensor/battery reports
        self.batteryReport = controller.batteryReport()
        self.sensorReport = controller.sensors_report()
        self.displayReport = controller.displaysReport()
    }

    private var isEDRCapable: Bool {
        displayReport?.displays.contains { $0.edrCapable } ?? false
    }

    private var manualFanBinding: Binding<Bool> {
        Binding(
            get: { self.isFanManualMode },
            set: { newValue in
                self.isFanManualMode = newValue
                do {
                    if newValue {
                        try controller.applyFan(fraction: fanFraction)
                    } else {
                        try controller.restoreFanAuto()
                    }
                    fanError = nil
                } catch {
                    fanError = error.localizedDescription
                    self.isFanManualMode = !newValue
                }
            }
        )
    }

    private func getBatteryIcon() -> String {
        guard let rep = batteryReport, rep.present else {
            return "battery.0"
        }
        if rep.charging == true {
            return "battery.100.bolt"
        }
        if let pct = rep.currentCapacityPercent {
            if pct > 80 { return "battery.100" }
            if pct > 50 { return "battery.75" }
            if pct > 25 { return "battery.50" }
            return "battery.25"
        }
        return "battery.50"
    }

    private func getBatteryStateText() -> String {
        guard let rep = batteryReport, rep.present else {
            return "No Battery Detected"
        }
        let cap = rep.currentCapacityPercent.map { "\($0)%" } ?? "Unknown"
        let state = rep.charging == true ? "Charging" : "On Battery"
        return "\(cap) (\(state))"
    }

    private func getBatteryDetailsText() -> String {
        guard let rep = batteryReport, rep.present else {
            return "Desktop Mac"
        }
        let health = rep.healthPercent.map { "\($0)% Health" } ?? ""
        let cycles = rep.cycleCount.map { "\($0) Cycles" } ?? ""
        let sep = !health.isEmpty && !cycles.isEmpty ? " · " : ""
        return "\(health)\(sep)\(cycles)"
    }

    private func getThermalColor() -> Color {
        guard let pressure = sensorReport?.thermalPressure else {
            return SymairaColors.success
        }
        switch pressure.lowercased() {
        case "nominal": return SymairaColors.success
        case "fair": return SymairaColors.warning
        default: return SymairaColors.danger
        }
    }

    private func getSensorDetailsText() -> String? {
        guard let rep = sensorReport, !rep.temperatures.isEmpty || !rep.fans.isEmpty else {
            return "App Sandbox: Detailed sensors restricted"
        }
        // If available, format CPU / Fan info
        var parts: [String] = []
        if let cpu = rep.temperatures.first(where: { $0.label.contains("CPU") }) {
            parts.append(String(format: "CPU: %.1f°C", cpu.celsius))
        }
        if let fan = rep.fans.first {
            parts.append("Fan: \(fan.rpm) RPM")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// Colors definition
struct SymairaColors {
    static let bgDark = Color(red: 13/255, green: 12/255, blue: 10/255)
    static let bgPanel = Color(red: 18/255, green: 17/255, blue: 14/255)
    static let bgCard = Color(red: 26/255, green: 24/255, blue: 20/255)
    static let goldPrimary = Color(red: 229/255, green: 195/255, blue: 151/255)
    static let goldSecondary = Color(red: 248/255, green: 230/255, blue: 205/255)
    static let textPrimary = Color(red: 245/255, green: 244/255, blue: 240/255)
    static let textSecondary = Color(red: 181/255, green: 174/255, blue: 165/255)
    static let textMuted = Color(red: 110/255, green: 104/255, blue: 96/255)
    static let border = Color(red: 229/255, green: 195/255, blue: 151/255).opacity(0.08)
    static let borderStrong = Color(red: 229/255, green: 195/255, blue: 151/255).opacity(0.18)
    static let success = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)
    static let danger = Color(red: 239/255, green: 68/255, blue: 68/255)
}
