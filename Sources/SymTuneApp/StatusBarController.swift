@preconcurrency import AppKit
import SymTuneCore
import SwiftUI

/// Manages the menu-bar status item: icon and NSPopover dropdown view.
///
/// Clicking the status icon displays the custom SwiftUI-based popover panel
/// containing controls and system readouts.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let controller = TuneController()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        setupPopover()
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
        popover.contentViewController = NSHostingController(rootView: MainStatusView(controller: controller))
        popover.behavior = .transient
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Activate the app to ensure UI focus
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
