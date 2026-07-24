@preconcurrency import AppKit
import SymTuneCore
import SwiftUI
import SymairaUpdateCheck

/// Manages the menu-bar status item: icon and NSPopover dropdown view.
///
/// Clicking the status icon displays the custom SwiftUI-based popover panel
/// containing controls and system readouts.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let controller = TuneController()
    let updateChecker = AppUpdateChecker(
        checker: UpdateChecker(owner: "danieljustus", repo: "symaira-tune"),
        store: UserDefaultsSkippedVersionStore(key: "com.symaira.tune.updateSkippedTag"),
        currentVersion: { TuneVersion.current }
    )

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        setupPopover()
        checkForUpdatesOnLaunch()
    }

    // MARK: - Update checking

    private func checkForUpdatesOnLaunch() {
        Task {
            await updateChecker.checkForUpdate()
            await MainActor.run { updateStatusItemBadge() }
        }
    }

    /// Show a subtle badge on the status icon when an update is available.
    private func updateStatusItemBadge() {
        guard case .available = updateChecker.status else { return }
        guard let button = statusItem.button else { return }
        // Draw a small indicator — use a dot attached to the icon
        button.attributedTitle = NSAttributedString(
            string: "\u{26A0}\u{FE0F}",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .baselineOffset: 8.0,
            ]
        )
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
        let hosting = NSHostingController(rootView: MainStatusView(controller: controller, updateChecker: updateChecker))
        // Without preferredContentSize sizing, the SwiftUI content reports its
        // height only after the popover is shown (and again on every periodic
        // refresh), so the popover window gets anchored with a stale frame and
        // ends up clipped above the menu bar instead of hanging below the icon.
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        popover.behavior = .transient
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
        }
    }
}
