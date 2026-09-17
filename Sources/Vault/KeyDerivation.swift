// NuDefndr - nudefndr.com
// Transparency Repository - Key derivation primitives (v2.6.3)

import Foundation
import Security
import CommonCrypto
import CryptoKit

enum KeyDerivation {
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

    static func subkey(from key: SymmetricKey, info: String, byteCount: Int = 32) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            info: Data(info.utf8),
            outputByteCount: byteCount
        )
    }

    static func randomBytes(_ count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return status == errSecSuccess ? Data(bytes) : nil
    }
}
