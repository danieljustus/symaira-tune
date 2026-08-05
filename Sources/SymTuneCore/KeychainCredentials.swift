import Foundation
import Security

/// Keychain access for provider credentials.
///
/// Credentials live in the macOS Keychain, never in `config.toml` or any
/// other plain-text file. Reading is the only operation the provider stack
/// performs automatically; writing happens only from an explicit user
/// action in the app's preferences.
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

    /// Stores a generic-password item, replacing an existing value.
    /// Returns `false` when the Keychain rejected the write (e.g. locked).
    /// - Parameters:
    ///   - service: keychain service name (e.g. `com.symaira.symtune`).
    ///   - account: credential slot (e.g. `openrouter-api-key`).
    ///   - value: the secret to store.
    public static func write(service: String, account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Deletes a generic-password item. Returns `true` when absent or removed.
    public static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
