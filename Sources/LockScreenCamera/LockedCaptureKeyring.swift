// NuDefndr - nudefndr.com
// Transparency Repository - Lock Screen camera keyring, sealed under the vault key (v2.6.9)

import CryptoKit
import Foundation

struct LockedCaptureKeyring: Sendable {
    struct Entry: Codable, Sendable {
        let id: Data
        let privateKey: Data
        let created: Date
    }

    enum KeyringError: Error, Equatable {
        case foreign
        case unreadable
    }

    static let fileName = "capture.keyring"
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
    static let pruneGrace: TimeInterval = 7 * 24 * 60 * 60
    static let retainedKeys = 24
    private static let label = Data("NUDEFNDR capture keyring v1".utf8)

    private(set) var entries: [Entry]
    private(set) var currentID: Data

    var currentPublicKey: Data {
        guard let entry = entries.first(where: { $0.id == currentID }),
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: entry.privateKey) else {
            return Data()
        }
        return key.publicKey.rawRepresentation
    }

    var currentCreated: Date {
        entries.first(where: { $0.id == currentID })?.created ?? .distantPast
    }

    var ids: Set<Data> { Set(entries.map(\.id)) }

    static func fresh(now: Date = Date()) -> LockedCaptureKeyring {
        let entry = makeEntry(now: now)
        return LockedCaptureKeyring(entries: [entry], currentID: entry.id)
    }

    mutating func rotate(now: Date = Date()) {
        let entry = Self.makeEntry(now: now)
        entries.append(entry)
        currentID = entry.id
    }

    @discardableResult
    mutating func prune(keepingReferenced referenced: Set<Data>, retaining: Int = Self.retainedKeys) -> Bool {
        let before = entries.count
        var excess = entries.count - max(retaining, 1)
        guard excess > 0 else { return false }
        entries = entries.sorted { $0.created < $1.created }.filter { entry in
            guard excess > 0, entry.id != currentID, !referenced.contains(entry.id) else { return true }
            excess -= 1
            return false
        }
        return entries.count != before
    }

    static func keyringKey(from vaultKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: vaultKey,
                               info: Data("NUDEFNDR capture keyring key v1".utf8),
                               outputByteCount: 32)
    }

    func privateKey(for id: Data) -> Curve25519.KeyAgreement.PrivateKey? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: entry.privateKey)
    }

    private static func makeEntry(now: Date) -> Entry {
        let key = Curve25519.KeyAgreement.PrivateKey()
        var id = Data(count: LockedCaptureFormat.keyIDLength)
        let status = id.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, LockedCaptureFormat.keyIDLength, $0.baseAddress!)
        }
        if status != errSecSuccess {
            id = Data(SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.prefix(LockedCaptureFormat.keyIDLength))
        }
        return Entry(id: id, privateKey: key.rawRepresentation, created: now)
    }

    private struct Stored: Codable {
        let version: Int
        let currentID: Data
        let currentPublicKey: Data
        let sealed: Data
    }

    static func fileURL(in vaultDirectory: URL) -> URL {
        vaultDirectory.appendingPathComponent(fileName)
    }

    enum Published: Equatable {
        case absent
        case key(keyID: Data, publicKey: Data)
        case unknown
    }

    static func published(in vaultDirectory: URL) -> Published {
        let url = fileURL(in: vaultDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == 1,
              stored.currentID.count == LockedCaptureFormat.keyIDLength,
              stored.currentPublicKey.count == 32 else { return .unknown }
        return .key(keyID: stored.currentID, publicKey: stored.currentPublicKey)
    }

    static func publishedKey(in vaultDirectory: URL) -> (keyID: Data, publicKey: Data)? {
        if case .key(let id, let key) = published(in: vaultDirectory) { return (id, key) }
        return nil
    }

    static func open(in vaultDirectory: URL, using vaultKey: SymmetricKey) throws -> LockedCaptureKeyring? {
        let url = fileURL(in: vaultDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw KeyringError.unreadable }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == 1,
              stored.currentID.count == LockedCaptureFormat.keyIDLength,
              stored.currentPublicKey.count == 32,
              let box = try? ChaChaPoly.SealedBox(combined: stored.sealed) else { throw KeyringError.unreadable }
        let aad = label + stored.currentID + stored.currentPublicKey
        guard let plaintext = try? ChaChaPoly.open(box, using: keyringKey(from: vaultKey), authenticating: aad) else {
            throw KeyringError.foreign
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: plaintext) else { throw KeyringError.unreadable }
        let ring = LockedCaptureKeyring(entries: entries, currentID: stored.currentID)
        guard !ring.currentPublicKey.isEmpty, ring.currentPublicKey == stored.currentPublicKey else {
            throw KeyringError.unreadable
        }
        return ring
    }

    func save(in vaultDirectory: URL, using vaultKey: SymmetricKey) throws {
        let publicKey = currentPublicKey
        let aad = Self.label + currentID + publicKey
        let plaintext = try JSONEncoder().encode(entries)
        let sealed = try ChaChaPoly.seal(plaintext, using: Self.keyringKey(from: vaultKey), authenticating: aad).combined
        let stored = Stored(version: 1, currentID: currentID, currentPublicKey: publicKey, sealed: sealed)
        try JSONEncoder().encode(stored).write(to: Self.fileURL(in: vaultDirectory),
                                              options: [.atomic, .completeFileProtection])
    }
}
