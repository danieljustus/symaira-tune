import SwiftUI
import SymTuneCore

/// Keep Awake session card: status indicator, duration picker, display-sleep
/// toggle, and start/end button. Extracted from MainStatusView to keep the
/// main view under the type-body-length limit.
struct KeepAwakeCard: View {
    /// Whether a keep-awake session is currently active.
    @Binding var active: Bool
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
        VStack(spacing: 10) {
            HStack {
                Label("Keep Awake", systemImage: active ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? SymairaColors.goldPrimary : SymairaColors.textSecondary)
                Spacer()
                // Status indicator
                Circle()
                    .fill(active ? SymairaColors.success : SymairaColors.danger.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(active ? "Active" : "Inactive")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? SymairaColors.success : SymairaColors.textMuted)
                if active, let remaining = remaining {
                    Text("· \(remaining)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SymairaColors.textMuted)
                }
                .toggleStyle(.switch)
                .disabled(!isInteractive)
            }

            // Start / End button
            Button(action: onToggle) {
                Text(active ? "End Session" : "Start Session")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? SymairaColors.danger : SymairaColors.bgDark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(active ? SymairaColors.danger.opacity(0.15) : SymairaColors.goldPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(SymairaColors.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(active ? SymairaColors.goldPrimary.opacity(0.3) : SymairaColors.border, lineWidth: 1)
        )
    }
}
