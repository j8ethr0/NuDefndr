// NuDefndr - nudefndr.com
// Transparency Repository - Vault key storage (v2.6.3)

import Foundation
import Security
import CryptoKit

struct KeychainHelper {
    static func saveKey(_ key: SymmetricKey, forName name: String) -> Bool {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: name,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        let success = status == errSecSuccess

        if success {
            AppLogger.security.debug("Encryption key saved to Keychain")
        } else {
            AppLogger.security.error("Failed to save key to Keychain (status: \(status, privacy: .public))")
        }

        return success
    }

    enum KeyLoadResult {
        case found(SymmetricKey)
        case absent
        case failed(OSStatus)
    }

    static func loadKeyResult(forName name: String) -> KeyLoadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: name,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        switch status {
        case errSecSuccess:
            guard let retrievedData = dataTypeRef as? Data else {
                AppLogger.security.error("Keychain returned success with no key data")
                return .failed(status)
            }
            AppLogger.security.debug("Successfully loaded key from Keychain")
            return .found(SymmetricKey(data: retrievedData))
        case errSecItemNotFound:
            return .absent
        default:
            AppLogger.security.error("Keychain key read failed (status: \(status, privacy: .public))")
            return .failed(status)
        }
    }

    static func loadKey(forName name: String) -> SymmetricKey? {
        if case .found(let key) = loadKeyResult(forName: name) { return key }
        return nil
    }

    @discardableResult
    static func deleteKey(forName name: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: name
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
