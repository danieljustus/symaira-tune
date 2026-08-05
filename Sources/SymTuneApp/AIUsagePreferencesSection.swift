import SwiftUI
import SymairaTheme
import SymTuneCore

/// The AI-usage block of the preferences window: per-provider toggles
/// (default off — no network calls until enabled), API-key fields that write
/// to the Keychain, the menu-bar readout toggle, and the refresh interval.
/// Extracted from ``PreferencesView`` to keep that file under the line cap.
struct AIUsagePreferencesSection: View {
    @ObservedObject var preferences: AIUsagePreferences
    let providerCatalog: [(id: String, displayName: String)]

    /// Providers whose credentials are plain API keys stored in the Keychain
    /// (service `com.symaira.symtune`), shown as SecureFields here. Tokens
    /// managed by their own CLI/OAuth flows (Codex, Claude, Copilot, …) have
    /// no field.
    private static func apiKeyField(for providerID: String) -> (label: String, placeholder: String)? {
        switch providerID {
        case "moonshot":
            return ("Moonshot API key", "sk-…")
        case "openrouter":
            return ("OpenRouter API key", "sk-or-…")
        case "kimi":
            return ("Kimi Code API key", "kimi-…")
        default:
            return nil
        }
    }

    private func binding(for providerID: String) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(providerID) },
            set: { preferences.setEnabled(providerID, $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Usage")
                .symairaText(.subheading)
                .foregroundStyle(SymairaTheme.textPrimary)

            Text("Track AI subscription usage per provider. Disabled providers make no network calls; credentials live in the Keychain, never in config.toml.")
                .symairaText(.caption)
                .foregroundStyle(SymairaTheme.textSecondary)

            ForEach(providerCatalog, id: \.id) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: binding(for: provider.id)) {
                        Text(provider.displayName)
                            .symairaText(.body)
                            .foregroundStyle(SymairaTheme.textPrimary)
                    }
                    .tint(SymairaTheme.goldPrimary)

                    if preferences.isEnabled(provider.id),
                       let keyField = Self.apiKeyField(for: provider.id) {
                        APIKeyField(
                            providerID: provider.id,
                            label: keyField.label,
                            placeholder: keyField.placeholder
                        )
                    }
                }
            }

            Toggle(isOn: $preferences.menuBarEnabled) {
                Text("Show AI usage in the menu bar")
                    .symairaText(.body)
                    .foregroundStyle(SymairaTheme.textPrimary)
            }
            .tint(SymairaTheme.goldPrimary)

            HStack {
                Text("Refresh interval")
                    .symairaText(.body)
                    .foregroundStyle(SymairaTheme.textPrimary)
                Spacer()
                Picker("", selection: $preferences.refreshInterval) {
                    ForEach(AIUsagePreferences.intervalOptions, id: \.self) { interval in
                        Text("\(Int(interval / 60)) min").tag(interval)
                    }
                }
                .labelsHidden()
            }
        }
    }
}
