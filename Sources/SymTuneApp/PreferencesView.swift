import SwiftUI
import SymTuneCore
import SymairaUpdateCheck

/// Preferences window for configuring which system metrics are monitored,
/// shown in the menu bar, their order, refresh interval, and display units.
struct PreferencesView: View {
    @ObservedObject var manager: PreferencesManager
    let autoPrefs: UserDefaultsAutoUpdatePreferenceStore

    @State private var refreshText: String = ""
    @State private var applyMessage: String?
    @State private var applySuccess: Bool = false
    @AppStorage("com.symaira.symtune.autoCheckEnabled") private var autoCheckEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .background(SymairaColors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Metrics list with toggles and ordering
                    metricsSection

                    Divider()
                        .background(SymairaColors.border)

                    // Refresh interval
                    refreshIntervalSection

                    Divider()
                        .background(SymairaColors.border)

                    // Units
                    unitsSection

                    Divider()
                        .background(SymairaColors.border)

                    // Auto-update
                    updateSection
                }
                .padding(20)
            }

            Divider()
                .background(SymairaColors.border)

            // Footer with apply button
            footerView
        }
        .frame(width: 420, height: 480)
        .background(SymairaColors.bgDark)
        .onAppear {
            refreshText = String(format: "%.1f", manager.metricsRefreshInterval)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preferences")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SymairaColors.goldPrimary)
                Text("System Metrics")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Metrics Section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MONITORED METRICS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SymairaColors.textMuted)

            Text("Drag to reorder, toggle to enable/disable or show/hide in the menu bar.")
                .font(.system(size: 10))
                .foregroundStyle(SymairaColors.textSecondary)

            // Metric rows
            VStack(spacing: 6) {
                ForEach(manager.metricOrder, id: \.self) { metric in
                    metricRow(metric)
                }
            }
        }
    }

    private func metricRow(_ metric: MetricIdentifier) -> some View {
        let isEnabled = manager.enabledMetrics.contains(metric)
        let isVisible = manager.visibleMetrics.contains(metric)
        let isFirst = manager.metricOrder.first == metric
        let isLast = manager.metricOrder.last == metric

        return HStack(spacing: 10) {
            // Move up/down buttons
            VStack(spacing: 2) {
                Button(action: { moveMetric(metric, up: true) }, label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 14)
                })
                .buttonStyle(.plain)
                .disabled(isFirst)
                .opacity(isFirst ? 0.3 : 0.8)
                .foregroundStyle(SymairaColors.textSecondary)

                Button(action: { moveMetric(metric, up: false) }, label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 14)
                })
                .buttonStyle(.plain)
                .disabled(isLast)
                .opacity(isLast ? 0.3 : 0.8)
                .foregroundStyle(SymairaColors.textSecondary)
            }

            // Metric name
            Text(metric.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isEnabled ? SymairaColors.textPrimary : SymairaColors.textMuted)
                .frame(width: 60, alignment: .leading)

            Spacer()

            // Enable/disable toggle
            Toggle(isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    if newValue {
                        manager.enabledMetrics.insert(metric)
                    } else {
                        manager.enabledMetrics.remove(metric)
                        manager.visibleMetrics.remove(metric)
                    }
                }
            )) {
                Text("Monitor")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)
            }
            .toggleStyle(.switch)
            .frame(width: 100)

            // Show/hide toggle
            Toggle(isOn: Binding(
                get: { isVisible },
                set: { newValue in
                    if newValue {
                        manager.enabledMetrics.insert(metric)
                        manager.visibleMetrics.insert(metric)
                    } else {
                        manager.visibleMetrics.remove(metric)
                    }
                }
            )) {
                Text("Show")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)
            }
            .toggleStyle(.switch)
            .frame(width: 80)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SymairaColors.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isEnabled ? SymairaColors.border : SymairaColors.border.opacity(0.3), lineWidth: 1)
        )
    }

    private func moveMetric(_ metric: MetricIdentifier, up: Bool) {
        guard let index = manager.metricOrder.firstIndex(of: metric) else { return }
        let newIndex = up ? max(0, index - 1) : min(manager.metricOrder.count - 1, index + 1)
        guard newIndex != index else { return }
        manager.metricOrder.move(fromOffsets: IndexSet(integer: index), toOffset: newIndex > index ? newIndex + 1 : newIndex)
    }

    // MARK: - Refresh Interval

    private var refreshIntervalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REFRESH INTERVAL")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SymairaColors.textMuted)

            HStack(spacing: 12) {
                Text("Sample every")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)

                TextField("", text: $refreshText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(SymairaColors.textPrimary)
                    .frame(width: 50)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SymairaColors.bgPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SymairaColors.borderStrong, lineWidth: 1)
                    )
                    .onChange(of: refreshText) { _, newValue in
                        if let value = TimeInterval(newValue),
                           value >= TuneConfig.minimumRefreshInterval {
                            manager.metricsRefreshInterval = value
                        }
                    }

                Text("seconds")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)

                Spacer()

                // Quick presets
                ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { preset in
                    Button(action: {
                        manager.metricsRefreshInterval = preset
                        refreshText = String(format: "%.0f", preset)
                    }, label: {
                        Text("\(Int(preset))s")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                abs(manager.metricsRefreshInterval - preset) < 0.01
                                    ? SymairaColors.bgDark
                                    : SymairaColors.textSecondary
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                abs(manager.metricsRefreshInterval - preset) < 0.01
                                    ? SymairaColors.goldPrimary
                                    : SymairaColors.bgPanel
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    })
                    .buttonStyle(.plain)
                }
            }

            // Minimum interval note
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SymairaColors.textMuted)
                Text("Minimum refresh interval is \(String(format: "%.0f", TuneConfig.minimumRefreshInterval)) second")
                    .font(.system(size: 9))
                    .foregroundStyle(SymairaColors.textMuted)
            }
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DISPLAY UNITS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SymairaColors.textMuted)

            HStack(spacing: 24) {
                // Network unit
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network Throughput")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SymairaColors.textMuted)

                    Picker("", selection: $manager.networkUnit) {
                        ForEach(NetworkUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Spacer()

                // Temperature unit
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temperature")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SymairaColors.textMuted)

                    Picker("", selection: $manager.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
        }
    }

    // MARK: - Auto-Update Section

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UPDATE CHECK")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SymairaColors.textMuted)

            HStack {
                Toggle(isOn: $autoCheckEnabled) {
                    Text("Automatisch nach Updates suchen")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SymairaColors.textPrimary)
                }
                .toggleStyle(.switch)
                Spacer()
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Apply message
            if let message = applyMessage {
                HStack(spacing: 4) {
                    Image(systemName: applySuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(applySuccess ? SymairaColors.success : SymairaColors.danger)
                    Text(message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(applySuccess ? SymairaColors.success : SymairaColors.danger)
                }
            }

            Spacer()

            Button(action: {
                NSApp.keyWindow?.close()
            }, label: {
                Text("Close")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SymairaColors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(SymairaColors.bgPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SymairaColors.border, lineWidth: 1)
                    )
            })
            .buttonStyle(.plain)

            Button(action: applyPreferences) {
                Text("Apply & Save")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SymairaColors.bgDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(SymairaColors.goldPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func applyPreferences() {
        do {
            try manager.writeToConfig()
            applyMessage = "Preferences saved — changes take effect immediately."
            applySuccess = true
        } catch {
            applyMessage = "Failed to save preferences: \(error.localizedDescription)"
            applySuccess = false
        }

        // Clear message after a few seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            applyMessage = nil
        }
    }
}
