import Foundation
import Combine

/// AI-usage preferences for the menu-bar app.
///
/// UserDefaults-backed; every provider toggle defaults to **off** so no
/// network call happens until the user explicitly enables a provider.
@MainActor
final class AIUsagePreferences: ObservableObject {
    /// Providers the user enabled (default: none).
    @Published var enabledProviders: Set<String> {
        didSet { defaults.set(Array(enabledProviders), forKey: Keys.enabledProviders) }
    }

    /// Refresh interval in seconds (default 5 minutes).
    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    /// Whether the menu bar shows a compact AI usage readout.
    @Published var menuBarEnabled: Bool {
        didSet { defaults.set(menuBarEnabled, forKey: Keys.menuBarEnabled) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabledProviders = "com.symaira.symtune.aiUsage.enabledProviders"
        static let refreshInterval = "com.symaira.symtune.aiUsage.refreshInterval"
        static let menuBarEnabled = "com.symaira.symtune.aiUsage.menuBarEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabledProviders = Set(defaults.stringArray(forKey: Keys.enabledProviders) ?? [])
        let stored = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = stored > 0 ? stored : 300
        self.menuBarEnabled = defaults.bool(forKey: Keys.menuBarEnabled)
    }

    /// The user-facing refresh interval options (minutes).
    static let intervalOptions: [TimeInterval] = [60, 120, 300, 600, 1800, 3600]

    /// Whether a provider is enabled.
    func isEnabled(_ providerID: String) -> Bool {
        enabledProviders.contains(providerID)
    }

    /// Toggles a provider on or off. Disabling never clears the Keychain
    /// credentials — re-enabling stays frictionless.
    func setEnabled(_ providerID: String, _ enabled: Bool) {
        if enabled {
            enabledProviders.insert(providerID)
        } else {
            enabledProviders.remove(providerID)
        }
    }
}
