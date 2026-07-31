// NudeFndr - nudefndr.com
// Transparency Repository - Vault encryption using Apple CryptoKit

import Foundation
import CryptoKit
import CommonCrypto

/// Vault encryption using ChaCha20-Poly1305 (AEAD cipher)
/// Standard Apple CryptoKit implementation - no proprietary code
final class VaultEncryption {
	
	enum EncryptionError: Error {
		case encryptionFailed
		case decryptionFailed
		case invalidData
	}
	
	/// Encrypt data using ChaCha20-Poly1305 (256-bit AEAD)
	/// Provides both confidentiality and authenticity
	static func encrypt(data: Data, key: SymmetricKey) throws -> Data {
		let sealedBox = try ChaChaPoly.seal(data, using: key)
		return sealedBox.combined
	}
	
	/// Decrypt data using ChaCha20-Poly1305
	/// Automatically verifies authentication tag
	static func decrypt(data: Data, key: SymmetricKey) throws -> Data {
		let sealedBox = try ChaChaPoly.SealedBox(combined: data)
		return try ChaChaPoly.open(sealedBox, using: key)
	}
	
	/// Generate a cryptographically secure 256-bit encryption key
	static func generateKey() -> SymmetricKey {
		return SymmetricKey(size: .bits256)
	}
	
	/// Derive a key from a password using PBKDF2.
	///
	/// NOTE: this is a general-purpose helper and is **not** the vault's key path.
	/// The vault key is random (`generateKey()` above) and lives in the Keychain —
	/// it is not derived from a PIN or passphrase, so PIN strength is not the
	/// vault's cryptographic strength.
	///
	/// Where the shipping app actually runs PBKDF2-HMAC-SHA256, and at what cost:
	///   * PIN credentials (Vault / Panic / Distress PINs): 310,000 iterations
	///   * Passphrase wrapping an exported key-backup file: 600,000 iterations
	///     — see `VaultKeyBackup.swift` in this repository.
	/// The 100,000 below is the floor this helper was written against; do not read
	/// it as the app's PIN or key-backup work factor.
	static func deriveKey(from password: String, salt: Data) throws -> SymmetricKey {
		guard let passwordData = password.data(using: .utf8) else {
			throw EncryptionError.invalidData
		}
		
		var derivedKeyData = Data(count: 32)
		let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
			salt.withUnsafeBytes { saltBytes in
				CCKeyDerivationPBKDF(
					CCPBKDFAlgorithm(kCCPBKDF2),
					password, passwordData.count,
					saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
					CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
					100_000, // OWASP recommended iterations
					derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
				)
			}
		}
		
		guard result == kCCSuccess else {
			throw EncryptionError.encryptionFailed
		}
		
		return SymmetricKey(data: derivedKeyData)
	}
}