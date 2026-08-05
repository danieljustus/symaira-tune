import Foundation
import Security

/// Minimal read-only Keychain access for provider credentials.
///
/// Credentials live in the macOS Keychain, never in `config.toml` or any
/// other plain-text file. This type only reads; nothing in the AI-usage
/// stack ever writes secrets.
public enum KeychainCredentials {
    /// Reads a generic-password item, or `nil` when absent.
    /// - Parameters:
    ///   - service: keychain service name (e.g. `com.symaira.symtune`).
    ///   - account: credential slot (e.g. `openrouter-api-key`).
    public static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
