// NuDefndr - nudefndr.com
// Transparency Repository - Vault key backup & recovery (v2.6.3)

import Foundation
import Security
import CryptoKit

enum VaultKeyBackup {
    static let fileFormat = "nudefndr-vault-key"
    static let fileExtension = "nudefndrkey"
    private static let iterations = 600_000
    private static let minIterations = 100_000
    private static let maxIterations = 5_000_000
    private static let saltByteCount = 16
    private static let keyByteCount = 32
    private static let exportedFlagAccount = "com.dro1d.PicDefndr.hasExportedVaultKey"
    private static let exportedFlagAccount = "com.dro1d.PicDefndr.hasExportedVaultKey"

    struct BackupFile: Codable {
        let format: String
        let version: Int
        let root: String
        let salt: String
        let iterations: Int
        let wrappedKey: String
        let createdAt: String
    }

    enum BackupError: Error, LocalizedError {
        case noVaultKey
    enum BackupError: Error, LocalizedError {
        case noVaultKey
        case cryptoFailed
        case invalidFile
        case wrongPassphraseOrCorrupt
        case keychainSaveFailed

        var errorDescription: String? {
            switch self {
            case .noVaultKey:
                return "This vault has no key to export yet. Add something to your vault first, then try again."
            case .cryptoFailed:
                return "Something went wrong preparing the key. Please try again."
            case .invalidFile:
                return "That file isn't a NUDEFNDR vault key."
            case .wrongPassphraseOrCorrupt:
                return "Wrong passphrase, or the key file has been altered."
            case .keychainSaveFailed:
                return "Couldn't save the restored key to this device."
            }
        }
    }

    static var hasExportedKey: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: exportedFlagAccount,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess
    }

    static func exportPrimaryKey(passphrase: String) throws -> URL {
        guard let key = KeychainHelper.loadKey(forName: VaultRoot.primary.keychainName) else {
            throw BackupError.noVaultKey
        }
        let rawKeyData = key.withUnsafeBytes { Data($0) }

        guard let salt = KeyDerivation.randomBytes(saltByteCount),
              let wrappingKeyData = KeyDerivation.pbkdf2SHA256(password: passphrase, salt: salt, iterations: iterations, keyLength: keyByteCount) else {
            throw BackupError.cryptoFailed
        }
        let wrappingKey = SymmetricKey(data: wrappingKeyData)
        guard let sealed = try? AES.GCM.seal(rawKeyData, using: wrappingKey),
              let combined = sealed.combined else {
            throw BackupError.cryptoFailed
        }

        let file = BackupFile(
            format: fileFormat,
            version: 1,
            root: "primary",
            salt: salt.base64EncodedString(),
            iterations: iterations,
            wrappedKey: combined.base64EncodedString(),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else {
            throw BackupError.cryptoFailed
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NuDefndr-VaultKey.\(fileExtension)")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic, .completeFileProtection])

        setHasExportedKey(true)
        AppLogger.security.info("Vault key exported (wrapped)")
        return url
    }

    static func importKey(from url: URL, passphrase: String) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(BackupFile.self, from: data),
              file.format == fileFormat,
              file.iterations >= minIterations, file.iterations <= maxIterations,
              let salt = Data(base64Encoded: file.salt),
              let combined = Data(base64Encoded: file.wrappedKey) else {
            throw BackupError.invalidFile
        }

        guard let wrappingKeyData = KeyDerivation.pbkdf2SHA256(password: passphrase, salt: salt, iterations: file.iterations, keyLength: keyByteCount) else {
            throw BackupError.cryptoFailed
        }
        let wrappingKey = SymmetricKey(data: wrappingKeyData)

        let rawKeyData: Data
        do {
            let sealed = try AES.GCM.SealedBox(combined: combined)
            rawKeyData = try AES.GCM.open(sealed, using: wrappingKey)
        } catch {
            // AES-GCM authentication failure == wrong passphrase or tampered file.
            throw BackupError.wrongPassphraseOrCorrupt
        }
        guard rawKeyData.count == keyByteCount else {
            throw BackupError.wrongPassphraseOrCorrupt
        }

        let restoredKey = SymmetricKey(data: rawKeyData)
        guard KeychainHelper.saveKey(restoredKey, forName: VaultRoot.primary.keychainName) else {
            throw BackupError.keychainSaveFailed
        }
        setHasExportedKey(true)
        AppLogger.security.info("Vault key imported and installed")
    }

    static func setHasExportedKey(_ value: Bool) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: exportedFlagAccount
        ]
        SecItemDelete(base as CFDictionary)
        guard value else { return }
        var add = base
        add[kSecValueData as String] = Data([1])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
