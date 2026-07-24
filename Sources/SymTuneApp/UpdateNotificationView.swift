import SwiftUI
import SymairaUpdateCheck

/// A compact card view displayed when a newer release is available.
/// Shows the version tag, a Download button (opens the release URL),
/// and a Skip button (persists via the store so the version is never
/// re-prompted).
@MainActor
struct UpdateNotificationView: View {
    @ObservedObject var updateChecker: AppUpdateChecker

    var body: some View {
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
    }
}
