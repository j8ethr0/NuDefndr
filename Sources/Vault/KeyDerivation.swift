// NudeFndr - nudefndr.com
// Transparency Repository - Key derivation primitives (v2.6.1)

import Foundation
import Security
import CommonCrypto
import CryptoKit

/// Shared password-based key-derivation primitives used by the PIN credential store
/// and the vault-key backup. Centralised so there is exactly one vetted PBKDF2
/// implementation in the codebase.
enum KeyDerivation {

    /// PBKDF2-HMAC-SHA256. Returns `keyLength` derived bytes, or `nil` on failure.
    static func pbkdf2SHA256(password: String, salt: Data, iterations: Int, keyLength: Int) -> Data? {
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { saltRaw -> Int32 in
            derived.withUnsafeMutableBytes { outRaw in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, password.utf8.count,
                    saltRaw.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    outRaw.bindMemory(to: UInt8.self).baseAddress, keyLength
                )
            }
        }
        return status == kCCSuccess ? Data(derived) : nil
    }

    /// A purpose-specific subkey derived from an existing high-entropy key.
    ///
    /// HKDF, not PBKDF2: the two above stretch a *user passphrase*, which is why
    /// they cost 310k and 600k rounds. The input here is already a 256-bit
    /// `SymmetricKey` from the Keychain, so there is nothing to stretch and
    /// iterating would only add latency. HKDF-Expand is the right primitive for
    /// splitting one strong key into several independent ones.
    ///
    /// `info` is what makes the outputs independent. Two subkeys derived from the
    /// same vault key with different info strings cannot be used in place of one
    /// another, so a weakness in one context cannot be carried into the other —
    /// and a thumbnail key can never open a vault file.
    ///
    /// No salt: with a uniformly random input key, HKDF's salt buys nothing, and
    /// storing one would mean a second thing to keep in sync with the Keychain.
    /// The whole point of deriving is that there is nothing extra to persist.
    static func subkey(from key: SymmetricKey, info: String, byteCount: Int = 32) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            info: Data(info.utf8),
            outputByteCount: byteCount
        )
    }

    /// Cryptographically random bytes, or `nil` on RNG failure.
    static func randomBytes(_ count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return status == errSecSuccess ? Data(bytes) : nil
    }
}
