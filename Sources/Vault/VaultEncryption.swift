import Foundation
import CryptoKit

/// Vault encryption using AES-256-GCM and ChaCha20-Poly1305
/// Standard Apple CryptoKit implementation - no proprietary code
final class VaultEncryption {
    
    enum EncryptionError: Error {
        case encryptionFailed
        case decryptionFailed
        case invalidData
    }
    
    /// Encrypt data using ChaCha20-Poly1305
    static func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(data, using: key)
        return sealedBox.combined
    }
    
    /// Decrypt data using ChaCha20-Poly1305
    static func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
    
    /// Generate a 256-bit encryption key
    static func generateKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    /// Derive key from password using PBKDF2
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
                    100_000, // iterations
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
