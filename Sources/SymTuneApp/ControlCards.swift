import SwiftUI
import SymTuneCore

// MARK: - Display controls

/// Brightness / dim / warmth / extended-brightness sliders.
///
/// Each row owns its drag state (see ``TuneSliderRow``), so moving one slider
/// re-renders that row only — not this card, and not the panel around it.
struct DisplayControlsCard: View {
    let controller: TuneController
    let model: TuneViewModel

    private var isEDRCapable: Bool {
        model.displays.contains { $0.edrCapable }
    }

    var body: some View {
        VStack(spacing: 12) {
            TuneSliderRow(
                title: "Screen Brightness",
                systemImage: "sun.max.fill",
                value: model.builtinBrightness,
                range: 0.0...1.0
            ) { value in
                try? controller.applyBuiltinBrightness(value)
                model.refreshNow()
            }

            TuneSliderRow(
                title: "Software Dimming",
                systemImage: "moon.fill",
                value: model.dimAmount,
                range: 0.0...0.85
            ) { value in
                try? controller.applyDim(1.0 - value)
                model.refreshNow()
            }

            TuneSliderRow(
                title: "Color Warmth",
                systemImage: "thermometer.sun.fill",
                value: model.warmth,
                range: 0.0...1.0
            ) { value in
                try? controller.applyWarmth(value)
                model.refreshNow()
            }

            if isEDRCapable {
                TuneSliderRow(
                    title: "Extended Brightness",
                    systemImage: "sun.max.trianglebadge.exclamationmark.fill",
                    value: model.overrides.edrBrightness ?? 1.0,
                    range: 1.0...1.6
                ) { value in
                    try? controller.applyExtendedBrightness(value)
                    model.refreshNow()
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Fan control

struct FanControlCard: View {
    let controller: TuneController
    let model: TuneViewModel

    @State private var fanError: String?
    /// Mirrors the manual-mode switch so the toggle can revert on failure.
    @State private var manualOverride: Bool?

    private var hasFans: Bool {
        guard let fans = model.sensors?.fans else { return true }
        return !fans.isEmpty
    }

    private var isManualMode: Bool {
        manualOverride ?? (model.overrides.fanFraction != nil)
    }

    private var fanFraction: Double {
        model.overrides.fanFraction ?? 0.0
    }

    var body: some View {
        if hasFans {
            VStack(spacing: 12) {
                HStack {
                    Label("Fan Control", systemImage: "fanblades.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SymairaColors.textSecondary)
                    Spacer()
                    Toggle("", isOn: manualBinding)
                        .toggleStyle(.switch)
                }

                TuneSliderRow(
                    title: "Target Speed",
                    systemImage: "gauge.medium",
                    value: fanFraction,
                    range: 0.0...1.0,
                    isEnabled: isManualMode
                ) { value in
                    apply { try controller.applyFan(fraction: value) }
                }

                if let fanError {
                    Text(fanError)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SymairaColors.danger)
                        .padding(.top, 2)
                }
            }
            .cardStyle()
            .onChange(of: model.overrides.fanFraction) { _, _ in
                // The model is authoritative again once it reflects the change.
                manualOverride = nil
            }
        } else {
            VStack(spacing: 6) {
                HStack {
                    Label("Fan Control", systemImage: "fanblades.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SymairaColors.textSecondary)
                    Spacer()
                }
                Text("Not available on this Mac")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SymairaColors.textMuted)
            }
            .cardStyle()
        }
    }

    private var manualBinding: Binding<Bool> {
        Binding(
            get: { isManualMode },
            set: { newValue in
                manualOverride = newValue
                apply {
                    if newValue {
                        try controller.applyFan(fraction: fanFraction)
                    } else {
                        try controller.restoreFanAuto()
                    }
                } onFailure: {
                    manualOverride = !newValue
                }
            }
        )
    }

    private func apply(
        _ work: () throws -> Void,
        onFailure: () -> Void = {}
    ) {
        do {
            try work()
            fanError = nil
            model.refreshNow()
        } catch {
            fanError = error.localizedDescription
            onFailure()
        }
    }
}
