@preconcurrency import AppKit
import SymTuneCore
import SwiftUI
import SymairaUpdateCheck

/// Manages the menu-bar status item: icon and NSPopover dropdown view.
///
/// Clicking the status icon displays the custom SwiftUI-based popover panel
/// containing controls and system readouts.
///
/// When metrics are enabled in Preferences, the status item displays live
/// system metrics (CPU, memory, disk, network) that update on the configured
/// interval. When no metrics are selected or all are unavailable, the app
/// falls back to the slider icon.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let controller = TuneController()
    let preferencesManager: PreferencesManager
    private var preferencesWindow: NSWindow?

    /// Timer that drives the periodic metrics refresh in the menu bar.
    private var metricsRefreshTimer: Timer?

    let updateChecker = AppUpdateChecker(
        checker: UpdateChecker(owner: "danieljustus", repo: "symaira-tune"),
        store: UserDefaultsSkippedVersionStore(key: "com.symaira.tune.updateSkippedTag"),
        currentVersion: { TuneVersion.current }
    )

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.preferencesManager = PreferencesManager(config: TuneConfig())
        super.init()
        configureButton()
        setupPopover()
        checkForUpdatesOnLaunch()
        startMetricsRefresh()
    }

    // MARK: - Update checking

    private func checkForUpdatesOnLaunch() {
        Task {
            await updateChecker.checkForUpdate()
            await MainActor.run { refreshMetricsDisplay() }
        }
    }

    // MARK: - Metrics display

    /// Start or restart the metrics refresh timer at the appropriate interval.
    private func startMetricsRefresh() {
        metricsRefreshTimer?.invalidate()
        let interval = effectiveRefreshInterval()
        metricsRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetricsDisplay()
            }
        }
        // Fire immediately so the menu bar is never stale on launch.
        refreshMetricsDisplay()
    }

    /// Return the effective refresh interval: fast when the popover is open,
    /// slow when it is closed to conserve CPU.
    private func effectiveRefreshInterval() -> TimeInterval {
        if popover.isShown {
            let configured = preferencesManager.metricsRefreshInterval
            return max(configured, TuneConfig.minimumRefreshInterval)
        }
        return 10.0
    }

    /// Read current metrics from the controller and render them into the status
    /// item button's attributed title. Falls back to the app icon when no
    /// visible metrics are selected or all are unavailable.
    private func refreshMetricsDisplay() {
        guard let button = statusItem.button else { return }

        let ordered = orderedVisibleMetrics()
        let report = controller.metricsReport()
        let available = ordered.filter { metricHasData($0, report: report) }

        if available.isEmpty {
            renderIconFallback(button: button)
            return
        }

        // Metrics mode: hide the icon image, show text
        button.image = nil

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let color = NSColor.labelColor

        let text = formatMetrics(report: report, identifiers: available)
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])

        // Append update-available badge if needed
        if case .available = updateChecker.status {
            attributed.append(NSAttributedString(
                string: " \u{26A0}\u{FE0F}",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    .baselineOffset: 1.0,
                    .foregroundColor: NSColor.systemYellow,
                ]
            ))
        }

        button.attributedTitle = attributed
    }

    /// Render the fallback icon (and update badge) when no metrics are available.
    private func renderIconFallback(button: NSStatusBarButton) {
        // Restore the icon image
        if let image = NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: "SymairaTune"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "ST"
        }

        // Show update badge if available
        if case .available = updateChecker.status {
            button.attributedTitle = NSAttributedString(
                string: "\u{26A0}\u{FE0F}",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                    .baselineOffset: 8.0,
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    /// Return the ordered list of visible metric identifiers.
    /// Falls back to CPU + Memory when nothing is configured.
    private func orderedVisibleMetrics() -> [MetricIdentifier] {
        let order = preferencesManager.metricOrder
        let visible = preferencesManager.visibleMetrics
        guard !visible.isEmpty, !order.isEmpty else {
            return [.cpu, .memory]
        }
        return order.filter { visible.contains($0) }
    }

    /// Check whether a metric identifier has usable data in the report.
    private func metricHasData(
        _ id: MetricIdentifier,
        report: SystemMetricsReport
    ) -> Bool {
        switch id {
        case .cpu: return report.cpu.totalUtilization != nil
        case .memory: return report.memory.usedBytes != nil
        case .disk: return report.disk != nil
        case .network:
            return report.network.aggregateBytesInPerSecond != nil
                || report.network.aggregateBytesOutPerSecond != nil
        default: return false
        }
    }

    /// Format a list of metrics into a compact single-line string for the menu bar.
    private func formatMetrics(
        report: SystemMetricsReport,
        identifiers: [MetricIdentifier]
    ) -> String {
        var parts: [String] = []
        for id in identifiers {
            switch id {
            case .cpu:
                if let util = report.cpu.totalUtilization {
                    parts.append("CPU \(String(format: "%2d%%", Int(util * 100)))")
                }
            case .memory:
                if let used = report.memory.usedBytes {
                    parts.append("RAM \(formatMemBytes(used))")
                }
            case .disk:
                if let d = report.disk {
                    let gb = Double(d.usedBytes) / 1_073_741_824.0
                    parts.append(String(format: "💾%.0fG", gb))
                }
            case .network:
                let down = report.network.aggregateBytesInPerSecond
                let up = report.network.aggregateBytesOutPerSecond
                if down != nil || up != nil {
                    var s = ""
                    if let d = down { s += "↓\(formatNetRate(d))" }
                    if let u = up {
                        if !s.isEmpty { s += " " }
                        s += "↑\(formatNetRate(u))"
                    }
                    parts.append(s)
                }
            default: break
            }
        }
        return parts.isEmpty ? "" : parts.joined(separator: "  ")
    }

    // MARK: - Value formatters

    private func formatMemBytes(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1fG", Double(bytes) / 1_073_741_824.0)
        }
        return String(format: "%.0fM", Double(bytes) / 1_048_576.0)
    }

    private func formatNetRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSecond / 1_048_576.0)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%.0fK", bytesPerSecond / 1_024.0)
        }
        return String(format: "%.0fB", bytesPerSecond)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // Use a nice control sliders symbol to match the tuning nature of the app
        if let image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "SymairaTune") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "ST"
        }
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        let hosting = NSHostingController(rootView: MainStatusView(
            controller: controller,
            updateChecker: updateChecker,
            preferencesManager: preferencesManager,
            openPreferences: { [weak self] in self?.openPreferences() }
        ))
        // Without preferredContentSize sizing, the SwiftUI content reports its
        // height only after the popover is shown (and again on every periodic
        // refresh), so the popover window gets anchored with a stale frame and
        // ends up clipped above the menu bar instead of hanging below the icon.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        popover.behavior = .transient
        popover.delegate = self
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Show first, then activate: activating an LSUIElement app before
            // the popover is anchored can misplace the popover window.
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            // Boost the refresh interval now that the popover is open
            startMetricsRefresh()
        }
    }

    /// Open the Preferences window.
    func openPreferences() {
        if let window = preferencesWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesView(manager: preferencesManager)
        let hosting = NSHostingController(rootView: prefsView)

        let window = NSWindow(contentViewController: hosting)
        window.title = "SymairaTune Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 420, height: 480))
        window.isReleasedWhenClosed = false
        window.center()

        self.preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // Slow down the refresh timer when the popover closes
        startMetricsRefresh()
    }
}
