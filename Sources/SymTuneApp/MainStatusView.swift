import SwiftUI
import SymTuneCore
import SymairaTheme
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

    /// Height budget for the popover, from the screen the menu bar is on.
    /// The panel grows with its content up to this cap and scrolls beyond it —
    /// `NSPopover` neither reflows nor scrolls oversized content, it just
    /// positions the window so the overflow (header first) falls off-screen.
    let maxHeight: CGFloat

    @State private var keepAwakeDurationIndex = 0
    @State private var keepAwakePreventDisplaySleep = false

    var body: some View {
        ScrollView(.vertical) {
            cards
        }
        .frame(width: 320)
        .frame(maxHeight: maxHeight)
        .background(SymairaTheme.bgDark)
        .onAppear {
            keepAwakePreventDisplaySleep = model.keepAwake.preventDisplaySleep
        }
    }

    private var cards: some View {
        VStack(spacing: SymairaSpacing.medium) {
            StatusHeaderView()

            Divider()
                .background(SymairaTheme.goldPrimary.opacity(0.15))

            if shows(.displayControls) {
                DisplayControlsCard(controller: controller, model: model)
            }

            if shows(.keepAwake) {
                KeepAwakeCard(
                    active: model.keepAwake.active,
                    preventDisplaySleep: $keepAwakePreventDisplaySleep,
                    durationIndex: $keepAwakeDurationIndex,
                    remaining: keepAwakeRemaining,
                    isInteractive: !model.keepAwake.active,
                    presets: Self.keepAwakePresets,
                    onToggle: toggleKeepAwake
                )
            }

            if shows(.fanControl, hardwareAvailable: hasFans) {
                FanControlCard(controller: controller, model: model)
            }

            if shows(.systemStatus) {
                SystemStatusCard(battery: model.battery, sensors: model.sensors)
                    .equatable()
            }

            // Never hidden: an available update is the one thing the user has
            // not opted out of seeing.
            UpdateNotificationView(updateChecker: updateChecker)

            if shows(.metricsHistory) {
                MetricsHistoryCard(rows: model.metricRows)
                    .equatable()
            }

            if shows(.displays) {
                DisplaysCard(displays: model.displays)
                    .equatable()
            }

            StatusFooterView(openPreferences: openPreferences)
        }
        .padding(SymairaSpacing.medium)
        .frame(width: 320)
    }

    // MARK: - Card visibility

    private func shows(_ card: PopoverCard, hardwareAvailable: Bool = true) -> Bool {
        preferencesManager.showsCard(card, hardwareAvailable: hardwareAvailable)
    }

    /// Whether this Mac reports any fan. `nil` sensors means "not read yet" —
    /// treated as present so the card does not flicker away on the first frame
    /// and back once the first sensor read lands.
    private var hasFans: Bool {
        guard let fans = model.sensors?.fans else { return true }
        return !fans.isEmpty
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
