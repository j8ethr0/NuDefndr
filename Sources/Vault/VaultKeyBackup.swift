// NudeFndr - nudefndr.com
// Transparency Repository - Vault key backup & recovery (v2.5.7)

import Foundation
import Security
import CommonCrypto
import CryptoKit

/// Export and restore of the vault encryption key.
///
/// The vault key lives in the Keychain as `WhenUnlockedThisDeviceOnly` — correct
/// for security (it never syncs to iCloud), but it also means a device wipe or an
/// iCloud-backup restore would leave an encrypted vault permanently unopenable.
/// This gives the user a deliberate, air-gapped recovery path:
///
///   1. The raw 256-bit vault key is wrapped with a key derived from a
///      user-chosen passphrase (PBKDF2-HMAC-SHA256, 600,000 iterations).
///   2. The wrapped key is sealed with AES-GCM (authenticated encryption).
///   3. The result is written to a `.nudefndrkey` file the user saves wherever
///      they choose — Files, an external drive, a second device.
///
/// Nothing is ever uploaded. The file is useless without the passphrase, and a
/// wrong passphrase fails the AES-GCM authentication tag rather than silently
/// producing a bad key. This mirrors the shipping implementation; app-specific
/// Keychain and logging plumbing is elided for clarity.
enum VaultKeyBackup {

    static let fileFormat = "nudefndr-vault-key"
    private static let iterations = 600_000
    private static let saltByteCount = 16
    private static let keyByteCount = 32

    struct BackupFile: Codable {
        let format: String
        let version: Int
        let salt: String        // base64, 16 random bytes
        let iterations: Int
        let wrappedKey: String  // base64 of the AES-GCM combined box (nonce + ciphertext + tag)
        let createdAt: String   // ISO-8601, informational only
    }

    enum BackupError: Error {
        case cryptoFailed
        case invalidFile
        case wrongPassphraseOrCorrupt
    }

    // MARK: - Export

    /// Wrap `rawVaultKey` with a key derived from `passphrase` and encode the
    /// `.nudefndrkey` payload. The caller writes the returned data to a file the
    /// user picks; it never touches the network.
    static func makeBackup(rawVaultKey: Data, passphrase: String) throws -> Data {
        guard let salt = randomBytes(saltByteCount),
              let wrappingKeyData = pbkdf2(passphrase: passphrase, salt: salt, iterations: iterations, keyLength: keyByteCount) else {
            throw BackupError.cryptoFailed
        }
        let wrappingKey = SymmetricKey(data: wrappingKeyData)

        guard let sealed = try? AES.GCM.seal(rawVaultKey, using: wrappingKey),
              let combined = sealed.combined else {
            throw BackupError.cryptoFailed
        }

        let file = BackupFile(
            format: fileFormat,
            version: 1,
            salt: salt.base64EncodedString(),
            iterations: iterations,
            wrappedKey: combined.base64EncodedString(),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { throw BackupError.cryptoFailed }
        return data
    }

    // MARK: - Import

    /// Recover the raw vault key from a `.nudefndrkey` payload. Throws
    /// `.wrongPassphraseOrCorrupt` when the passphrase is wrong or the file was
    /// tampered with — the AES-GCM authentication tag makes the two
    /// indistinguishable, by design.
    static func recoverKey(from fileData: Data, passphrase: String) throws -> Data {
        guard let file = try? JSONDecoder().decode(BackupFile.self, from: fileData),
              file.format == fileFormat,
              let salt = Data(base64Encoded: file.salt),
              let combined = Data(base64Encoded: file.wrappedKey) else {
            throw BackupError.invalidFile
        }

        guard let wrappingKeyData = pbkdf2(passphrase: passphrase, salt: salt, iterations: file.iterations, keyLength: keyByteCount) else {
            throw BackupError.cryptoFailed
        }
        let wrappingKey = SymmetricKey(data: wrappingKeyData)

        do {
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let raw = try AES.GCM.open(sealed, using: wrappingKey)
            guard raw.count == keyByteCount else { throw BackupError.wrongPassphraseOrCorrupt }
            return raw
        } catch {
            throw BackupError.wrongPassphraseOrCorrupt
        }
    }

    // MARK: - Primitives

    private static func pbkdf2(passphrase: String, salt: Data, iterations: Int, keyLength: Int) -> Data? {
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { saltRaw -> Int32 in
            derived.withUnsafeMutableBytes { outRaw in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase, passphrase.utf8.count,
                    saltRaw.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    outRaw.bindMemory(to: UInt8.self).baseAddress, keyLength
                )
            }
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    private static func randomBytes(_ count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        return SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess ? Data(bytes) : nil
    }
}
