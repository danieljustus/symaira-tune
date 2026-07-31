import SwiftUI
import SymairaTheme
import SymTuneCore

/// Keep Awake session card: status indicator, duration picker, display-sleep
/// toggle, and start/end button. Extracted from MainStatusView to keep the
/// main view under the type-body-length limit.
struct KeepAwakeCard: View {
    /// Whether a keep-awake session is currently active. Owned by the model —
    /// the card reports intent through `onToggle` and re-reads the result.
    let active: Bool
    /// Whether to prevent display sleep in addition to system sleep.
    @Binding var preventDisplaySleep: Bool
    /// Selected duration preset index (0 = indefinite).
    @Binding var durationIndex: Int
    /// Human-readable remaining time, or nil.
    let remaining: String?
    /// Whether the session controls should be interactive.
    let isInteractive: Bool
    /// Duration presets: (label, seconds).
    let presets: [(label: String, seconds: TimeInterval?)]
    /// Called when the start/end button is pressed.
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: CardMetrics.rowSpacing) {
            HStack {
                Label("Keep Awake", systemImage: active ? "lock.fill" : "lock.open.fill")
                    .symairaText(.subheading)
                    .foregroundStyle(active ? SymairaColors.goldPrimary : SymairaColors.textSecondary)
                Spacer()
                // Status indicator
                Circle()
                    .fill(active ? SymairaColors.success : SymairaColors.danger.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(active ? "Active" : "Inactive")
                    .symairaText(.caption)
                    .foregroundStyle(active ? SymairaColors.success : SymairaColors.textMuted)
                if active, let remaining = remaining {
                    Text("· \(remaining)")
                        .symairaText(.monoSmall)
                        .foregroundStyle(SymairaColors.goldSecondary)
                }
            }

            HStack(spacing: 8) {
                // Duration picker
                Picker("Duration", selection: $durationIndex) {
                    ForEach(0..<presets.count, id: \.self) { i in
                        Text(presets[i].label).tag(i)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(!isInteractive)

                // Display sleep toggle
                Toggle(isOn: $preventDisplaySleep) {
                    Text("Display")
                        .symairaText(.caption)
                        .foregroundStyle(SymairaColors.textMuted)
                }
                .toggleStyle(.switch)
                .disabled(!isInteractive)
            }

            // Start / End button
            Button(action: onToggle) {
                Text(active ? "End Session" : "Start Session")
                    .symairaText(.caption)
                    .foregroundStyle(active ? SymairaColors.danger : SymairaColors.bgDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(active ? SymairaColors.danger.opacity(0.15) : SymairaColors.goldPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .cardStyle(
            borderColor: active
                ? SymairaColors.goldPrimary.opacity(0.3)
                : SymairaColors.border
        )
    }
}
