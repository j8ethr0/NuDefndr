// NuDefndr - nudefndr.com
// Transparency Repository - PIN credential storage (v2.6.8)

import Foundation
import CryptoKit

enum PanicPinStore {
    private static let keychainAccount = "com.dro1d.PicDefndr.panicPinCredential"
    private static let iterations = 310_000
    private static let saltByteCount = 16
    private static let derivedKeyByteCount = 32

    private static let writeLock = NSLock()

    private struct Credential: Codable {
        let salt: Data
        let hash: Data
        let iterations: Int
    }

    static var isConfigured: Bool {
        if loadCredentialData() != nil { return true }
        return !legacyHash.isEmpty || !legacyPlaintext.isEmpty
    }

    @discardableResult
    static func set(pin: String) -> Bool {
        guard let credential = makeCredential(pin: pin) else { return false }
        return writeLock.withLock { commit(credential) }
    }

    private static func makeCredential(pin: String) -> Credential? {
        guard let salt = randomBytes(saltByteCount),
              let hash = derive(pin: pin, salt: salt, iterations: iterations) else {
            AppLogger.security.error("Panic PIN: failed to derive credential")
            return nil
        }
        return Credential(salt: salt, hash: hash, iterations: iterations)
    }

    private static func commit(_ credential: Credential) -> Bool {
        let stored = storeCredential(credential)
        if stored { purgeLegacy() }
        return stored
    }

    @discardableResult
    static func clear() -> Bool {
        writeLock.withLock {
            let removed = deleteCredential()
            purgeLegacy()
            return removed
        }
    }

    static func verify(pin: String) -> Bool {
        if let cred = loadCredential() {
            guard let candidate = derive(pin: pin, salt: cred.salt, iterations: cred.iterations) else {
                return false
            }
            return constantTimeEquals(candidate, cred.hash)
        }
        let hash = legacyHash
        if !hash.isEmpty {
            guard legacySHA256Hex(pin) == hash else { return false }
            set(pin: pin)
            AppLogger.security.info("Panic PIN upgraded to PBKDF2 (from legacy hash)")
            return true
        }
        let plaintext = legacyPlaintext
        if !plaintext.isEmpty {
            guard pin == plaintext else { return false }
            set(pin: pin)
            AppLogger.security.info("Panic PIN upgraded to PBKDF2 (from legacy plaintext)")
            return true
        }
        return false
    }

    static func migrateLegacyIfPossible() {
        if loadCredentialData() != nil {
            purgeLegacy()
            return
        }
        guard !legacyPlaintext.isEmpty || !legacyHash.isEmpty else { return }
        Task.detached(priority: .utility) { migrateLegacyNow() }
    }

    private static func migrateLegacyNow() {
        let plaintext = legacyPlaintext
        let hash = legacyHash
        guard let pin = plaintext.isEmpty ? recoverLegacyPIN(fromHash: hash) : plaintext else {
            if !hash.isEmpty {
                AppLogger.security.error("Panic PIN: legacy hash matched no 4-digit PIN; left for verify")
            }
            return
        }
        guard let credential = makeCredential(pin: pin) else { return }
        let migrated = writeLock.withLock {
            guard loadCredentialData() == nil, legacyPlaintext == plaintext, legacyHash == hash else { return false }
            return commit(credential)
        }
        if migrated { AppLogger.security.info("Panic PIN: migrated legacy credential to PBKDF2 at launch") }
    }

    private static func recoverLegacyPIN(fromHash hash: String) -> String? {
        let target = hash.lowercased()
        for n in 0..<10_000 {
            let pin = String(format: "%04d", n)
            if legacySHA256Hex(pin) == target { return pin }
        }
        return nil
    }

    private static func derive(pin: String, salt: Data, iterations: Int) -> Data? {
        KeyDerivation.pbkdf2SHA256(password: pin, salt: salt, iterations: iterations, keyLength: derivedKeyByteCount)
    }

    private static func randomBytes(_ count: Int) -> Data? {
        KeyDerivation.randomBytes(count)
    }

    private static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    private static func storeCredential(_ credential: Credential) -> Bool {
        guard let data = try? JSONEncoder().encode(credential) else { return false }
        return storeCredentialData(data)
    }

    private static func loadCredential() -> Credential? {
        guard let data = loadCredentialData(),
              let credential = try? JSONDecoder().decode(Credential.self, from: data) else {
            return nil
        }
        return credential
    }

    private static func storeCredentialData(_ data: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            AppLogger.security.error("Panic PIN: keychain store failed (status: \(status, privacy: .public))")
        }
        return status == errSecSuccess
    }

    private static func loadCredentialData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else {
            return nil
        }
        return data
    }

    @discardableResult
    private static func deleteCredential() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static var legacyHash: String {
        UserDefaults.standard.string(forKey: AppKeys.panicPinHash) ?? ""
    }

    private static var legacyPlaintext: String {
        UserDefaults.standard.string(forKey: AppKeys.panicPinCode) ?? ""
    }

    private static func purgeLegacy() {
        UserDefaults.standard.removeObject(forKey: AppKeys.panicPinHash)
        UserDefaults.standard.removeObject(forKey: AppKeys.panicPinCode)
    }

    private static func legacySHA256Hex(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}
