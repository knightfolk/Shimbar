import Foundation
import Security

// MARK: - KeychainError

/// Errors that can occur during Keychain operations.
enum KeychainError: LocalizedError {
    /// A save (add or update) operation failed with the given `OSStatus`.
    case saveFailed(OSStatus)

    /// A delete operation failed with the given `OSStatus`.
    case deleteFailed(OSStatus)

    /// The data retrieved from the Keychain was in an unexpected format.
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed: \(SecCopyErrorMessageString(status, nil) ?? "unknown error" as CFString)"
        case .deleteFailed(let status):
            return "Keychain delete failed: \(SecCopyErrorMessageString(status, nil) ?? "unknown error" as CFString)"
        case .unexpectedData:
            return "Unexpected data format in Keychain"
        }
    }
}

// MARK: - KeychainManager

/// Provides secure storage for API keys using the macOS Keychain.
///
/// Keys are stored as `kSecClassGenericPassword` items with a shared
/// ``service`` identifier. Each provider's key is differentiated by
/// its `account` (provider ID).
struct KeychainManager {

    /// The Keychain service name used for all Shimbar API keys.
    static let service = "com.shimbar.api-keys"

    // MARK: - Save

    /// Saves (or updates) an API key for the given provider.
    ///
    /// If a key already exists for the provider, it is updated in place.
    ///
    /// - Parameters:
    ///   - key: The API key string to store.
    ///   - providerId: A unique identifier for the provider (e.g. `"openai"`).
    /// - Throws: ``KeychainError/saveFailed(_:)`` if the operation fails.
    static func saveKey(_ key: String, forProvider providerId: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
        ]

        // Attempt to update an existing item first.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            // No existing item — add a new one.
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
            return
        }

        throw KeychainError.saveFailed(updateStatus)
    }

    // MARK: - Get

    /// Retrieves the stored API key for a provider.
    ///
    /// - Parameter providerId: The provider identifier to look up.
    /// - Returns: The stored API key string, or `nil` if none exists.
    static func getKey(forProvider providerId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }

    // MARK: - Delete

    /// Deletes the stored API key for a provider.
    ///
    /// - Parameter providerId: The provider identifier whose key
    ///   should be removed.
    /// - Throws: ``KeychainError/deleteFailed(_:)`` if the operation
    ///   fails for a reason other than the item not existing.
    static func deleteKey(forProvider providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerId,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - List Stored Providers

    /// Returns the provider IDs for all stored API keys.
    ///
    /// - Returns: An array of provider identifier strings that have
    ///   keys stored in the Keychain.
    static func storedProviderIds() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return []
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}
