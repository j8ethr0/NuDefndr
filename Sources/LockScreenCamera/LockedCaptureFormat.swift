// NuDefndr - nudefndr.com
// Transparency Repository - Lock Screen camera sealed capture format (HPKE) (v2.6.9)

import CryptoKit
import Foundation

enum LockedCaptureFormat {
    static let fileExtension = "nfcap"
    static let currentVersion: UInt8 = 1

    private static let magic = Data("NFLC".utf8)
    static let keyIDLength = 8
    private static let encapsulatedKeyLength = 32
    private static let headerLength = 4 + 1 + keyIDLength + 16 + encapsulatedKeyLength
    private static let info = Data("NUDEFNDR locked capture v1".utf8)
    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    enum FormatError: Error, Equatable {
        case truncated
        case notACapture
        case unsupportedVersion(UInt8)
        case badKey
    }

    struct Header: Equatable, Sendable {
        let version: UInt8
        let keyID: Data
        let captureID: UUID
    }

    struct Payload: Sendable {
        let captureID: UUID
        let capturedAt: Date
        let imageData: Data
    }

    static func seal(imageData: Data,
                     capturedAt: Date,
                     captureID: UUID = UUID(),
                     to publicKey: Data,
                     keyID: Data) throws -> (captureID: UUID, blob: Data) {
        guard keyID.count == keyIDLength,
              let recipient = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey) else {
            throw FormatError.badKey
        }
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: ciphersuite, info: info)
        let encapsulated = sender.encapsulatedKey
        guard encapsulated.count == encapsulatedKeyLength else { throw FormatError.badKey }

        var header = Data(capacity: headerLength)
        header.append(magic)
        header.append(currentVersion)
        header.append(keyID)
        header.append(captureID.bytes)
        header.append(encapsulated)

        let millis = UInt64(max(0, capturedAt.timeIntervalSince1970 * 1000).rounded())
        var plaintext = Data(capacity: 8 + imageData.count)
        withUnsafeBytes(of: millis.bigEndian) { plaintext.append(contentsOf: $0) }
        plaintext.append(imageData)

        let ciphertext = try sender.seal(plaintext, authenticating: header)
        return (captureID, header + ciphertext)
    }

    static func header(of blob: Data) throws -> Header {
        guard blob.count > headerLength else { throw FormatError.truncated }
        let bytes = Data(blob.prefix(headerLength))
        guard bytes.prefix(4) == magic else { throw FormatError.notACapture }
        let version = bytes[bytes.startIndex + 4]
        guard version == currentVersion else { throw FormatError.unsupportedVersion(version) }
        let keyStart = bytes.startIndex + 5
        let idStart = keyStart + keyIDLength
        let keyID = Data(bytes[keyStart..<idStart])
        let captureID = UUID(bytes: Data(bytes[idStart..<(idStart + 16)]))
        return Header(version: version, keyID: keyID, captureID: captureID)
    }

    static func open(_ blob: Data, with privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Payload {
        let parsed = try header(of: blob)
        let headerBytes = Data(blob.prefix(headerLength))
        let encapsulated = Data(headerBytes.suffix(encapsulatedKeyLength))
        let ciphertext = Data(blob.dropFirst(headerLength))

        var recipient = try HPKE.Recipient(privateKey: privateKey,
                                           ciphersuite: ciphersuite,
                                           info: info,
                                           encapsulatedKey: encapsulated)
        let plaintext = try recipient.open(ciphertext, authenticating: headerBytes)
        guard plaintext.count > 8 else { throw FormatError.truncated }

        let millis = plaintext.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Payload(captureID: parsed.captureID,
                       capturedAt: Date(timeIntervalSince1970: Double(millis) / 1000),
                       imageData: Data(plaintext.dropFirst(8)))
    }

    static func fileName(for captureID: UUID) -> String {
        "\(captureID.uuidString).\(fileExtension)"
    }
}

private extension UUID {
    var bytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    init(bytes: Data) {
        var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &raw) { $0.copyBytes(from: bytes.prefix(16)) }
        self.init(uuid: raw)
    }
}
