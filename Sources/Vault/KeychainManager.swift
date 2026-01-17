// NudeFndr - nudefndr.com
/// iOS Keychain manager with device-bound key storage
/// Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly (keys never backed up to iCloud)
///
/// Note: Biometric access control is intentionally NOT enforced on keychain items.
/// Face ID is optional for vault access in NudeFndr, so enforcing biometric keychain
/// protection would break non-biometric workflows. Keys remain device-bound via
/// kSecAttrAccessibleWhenUnlockedThisDeviceOnly.

import Foundation
import CryptoKit
import Security

final class KeychainManager {
    
    enum KeychainError: Error {
        case saveFailed
        case loadFailed
        case notFound
    }
    
    /// Save encryption key to keychain (device-bound, not backed up)
    static func saveKey(_ key: SymmetricKey, identifier: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing key first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }
    
    /// Load encryption key from keychain
    static func loadKey(identifier: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let keyData = result as? Data else {
            throw status == errSecItemNotFound ? KeychainError.notFound : KeychainError.loadFailed
        }
        
        return SymmetricKey(data: keyData)
    }
    
    /// Delete key from keychain
    static func deleteKey(identifier: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier
        ]
        SecItemDelete(query as CFDictionary)
    }
}