// NuDefndr - nudefndr.com
// Transparency Repository - Sealed album and label sidecar (v2.6.9)

import CryptoKit
import Foundation

struct VaultAlbum: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var itemIDs: [UUID]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), itemIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.itemIDs = itemIDs
    }
}

struct VaultAlbumBook: Codable, Equatable {
    var albums: [VaultAlbum] = []
    var labels: [String: String] = [:]

    func album(_ id: UUID) -> VaultAlbum? { albums.first { $0.id == id } }

    func resolvedItemIDs(_ albumID: UUID, existing: Set<UUID>) -> [UUID] {
        guard let album = album(albumID) else { return [] }
        return album.itemIDs.filter { existing.contains($0) }
    }

    func label(for itemID: UUID) -> String? {
        let value = labels[itemID.uuidString]
        return (value?.isEmpty ?? true) ? nil : value
    }

    mutating func prune(existing: Set<UUID>) {
        for index in albums.indices {
            albums[index].itemIDs.removeAll { !existing.contains($0) }
        }
        labels = labels.filter { key, _ in
            guard let id = UUID(uuidString: key) else { return false }
            return existing.contains(id)
        }
    }
}

enum VaultAlbumStore {
    static let fileName = "vault_albums.json"
    static let currentVersion = 2

    private static let keyInfo = "com.nudefndr.vaultAlbumKey.v1"
    private static let sealBinding = Data("nudefndr.vault_albums.v2".utf8)

    private struct File: Codable {
        var version: Int
        var albums: [VaultAlbum]
        var labels: [String: String]
    }

    private static func albumKey(from vaultKey: SymmetricKey) -> SymmetricKey {
        KeyDerivation.subkey(from: vaultKey, info: keyInfo)
    }

    static func load(from directory: URL, key vaultKey: SymmetricKey) -> VaultAlbumBook {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return VaultAlbumBook() }

        if let box = try? ChaChaPoly.SealedBox(combined: data),
           let plain = try? ChaChaPoly.open(box, using: albumKey(from: vaultKey), authenticating: sealBinding) {
            guard let file = try? JSONDecoder().decode(File.self, from: plain) else {
                AppLogger.vault.error("Album sidecar unreadable; continuing without albums")
                return VaultAlbumBook()
            }
            guard file.version <= currentVersion else {
                AppLogger.vault.notice("Album sidecar is from a newer build (v\(file.version, privacy: .public)); ignoring")
                return VaultAlbumBook()
            }
            return VaultAlbumBook(albums: file.albums, labels: file.labels)
        }

        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1 else {
            AppLogger.vault.error("Album sidecar unreadable; continuing without albums")
            return VaultAlbumBook()
        }
        let book = VaultAlbumBook(albums: file.albums, labels: file.labels)
        if save(book, to: directory, key: vaultKey) {
            AppLogger.vault.info("Album sidecar sealed")
        }
        return book
    }

    @discardableResult
    static func save(_ book: VaultAlbumBook, to directory: URL, key vaultKey: SymmetricKey) -> Bool {
        let url = directory.appendingPathComponent(fileName)
        let file = File(version: currentVersion, albums: book.albums, labels: book.labels)
        do {
            let plain = try JSONEncoder().encode(file)
            let sealed = try ChaChaPoly.seal(plain, using: albumKey(from: vaultKey), authenticating: sealBinding).combined
            try sealed.write(to: url, options: [.atomicWrite, .completeFileProtection])
            return true
        } catch {
            AppLogger.vault.error("Failed to write album sidecar: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func remove(from directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
