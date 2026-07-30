import SwiftUI
import SymTuneCore
import SymairaUpdateCheck

/// The status popover.
///
/// This view is deliberately thin: it only assembles cards and hands each one
/// the slice of model state it needs. All heavy lifting — hardware polling,
/// aggregation, formatting — happens in ``TuneViewModel`` once per refresh, and
/// the cards below are `Equatable` so an unchanged card is not re-rendered.
///
/// The previous version kept every value in one view's `@State` and rebuilt the
/// entire panel — four sparkline canvases included — on every state change,
/// which made slider drags cost a full-panel re-render per frame.
@MainActor
struct MainStatusView: View {
    let controller: TuneController
    let model: TuneViewModel
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject var preferencesManager: PreferencesManager
    let openPreferences: () -> Void

    /// Duration presets: indefinite + 15m, 30m, 1h, 2h, 4h, 8h
    private static let keepAwakePresets: [(label: String, seconds: TimeInterval?)] = [
        ("Indefinite", nil),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600),
        ("2 hours", 7200),
        ("4 hours", 14400),
        ("8 hours", 28800),
    ]

    @State private var keepAwakeDurationIndex = 0
    @State private var keepAwakePreventDisplaySleep = false

    var body: some View {
        VStack(spacing: 14) {
            StatusHeaderView()

            Divider()
                .background(SymairaColors.goldPrimary.opacity(0.15))

            DisplayControlsCard(controller: controller, model: model)

            KeepAwakeCard(
                active: model.keepAwake.active,
                preventDisplaySleep: $keepAwakePreventDisplaySleep,
                durationIndex: $keepAwakeDurationIndex,
                remaining: keepAwakeRemaining,
                isInteractive: !model.keepAwake.active,
                presets: Self.keepAwakePresets,
                onToggle: toggleKeepAwake
            )

            FanControlCard(controller: controller, model: model)

            SystemStatusCard(battery: model.battery, sensors: model.sensors)
                .equatable()

            UpdateNotificationView(updateChecker: updateChecker)

            MetricsHistoryCard(rows: model.metricRows)
                .equatable()

            DisplaysCard(displays: model.displays)
                .equatable()

            StatusFooterView(openPreferences: openPreferences)
        }
        .padding(16)
        .frame(width: 320)
        .background(SymairaColors.bgDark)
        .onAppear {
            keepAwakePreventDisplaySleep = model.keepAwake.preventDisplaySleep
        }
    }

    // MARK: - Keep awake

    private var keepAwakeRemaining: String? {
        let session = model.keepAwake
        guard session.active, let expiresAt = session.expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        guard remaining > 0 else { return "expiring…" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func toggleKeepAwake() {
        if model.keepAwake.active {
            controller.endKeepAwakeSession()
        } else {
            let duration = Self.keepAwakePresets[keepAwakeDurationIndex].seconds
            _ = try? controller.beginKeepAwakeSession(
                duration: duration,
                preventDisplaySleep: keepAwakePreventDisplaySleep,
                reason: "SymairaTune menu bar"
            )
        }
        model.refreshNow()
    }
}

// MARK: - Colors

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
