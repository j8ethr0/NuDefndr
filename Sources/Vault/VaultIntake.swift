// NuDefndr - nudefndr.com
// Transparency Repository - Vault intake: metadata strip, seal and write (v2.6.9)

import Foundation
import CryptoKit
import UIKit

struct VaultItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let encryptedFileName: String
    let originalAssetIdentifier: String?
    let dateAdded: Date
}

enum VaultIntakeError: Error {
    case metadataStripFailed
}

extension VaultManager {
    nonisolated private static func sealIntoVault(imageData: Data,
                                                  in vaultDir: URL,
                                                  using key: SymmetricKey,
                                                  originalAssetIdentifier: String?,
                                                  itemID: UUID = UUID(),
                                                  dateAdded: Date = Date()) throws -> VaultItem {
        guard let cleanData = MetadataPrivacyService.strippedImageData(from: imageData)
                ?? UIImage(data: imageData)?.jpegData(compressionQuality: 0.95) else {
            throw VaultIntakeError.metadataStripFailed
        }
        let newItemID = itemID
        let sealedBox = try Self.sealItem(cleanData, id: newItemID, using: key)
        let encryptedFileName = "\(newItemID.uuidString).encrypteddata"
        let fileURL = vaultDir.appendingPathComponent(encryptedFileName)
        do {
            try sealedBox.write(to: fileURL, options: [.completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }

        return VaultItem(id: newItemID,
                         encryptedFileName: encryptedFileName,
                         originalAssetIdentifier: originalAssetIdentifier,
                         dateAdded: dateAdded)
    }

    enum LockedCaptureIntake: Equatable {
        case stored
        case alreadyStored
        case vaultClosed
        case unusable
        case failed
    }

    func ingestLockedCapture(_ payload: LockedCaptureFormat.Payload,
                             wipeEpoch expectedEpoch: Int? = nil) async -> LockedCaptureIntake {
        retryIndexLoadIfNeeded()
        let epoch = expectedEpoch ?? wipeEpoch
        guard opensLockScreenCaptures, wipeEpoch == epoch, let key = encryptionKey,
              let dir = getVaultDirectory(for: .primary) else { return .vaultClosed }
        if vaultedItems.contains(where: { $0.id == payload.captureID }) { return .alreadyStored }

        let generation = lockGeneration
        let capturedAt = min(payload.capturedAt, Date())
        let imageData = payload.imageData
        let itemID = payload.captureID

        let item: VaultItem
        do {
            item = try await Task.detached(priority: .utility) {
                try VaultManager.sealIntoVault(imageData: imageData,
                                               in: dir,
                                               using: key,
                                               originalAssetIdentifier: nil,
                                               itemID: itemID,
                                               dateAdded: capturedAt)
            }.value
        } catch VaultIntakeError.metadataStripFailed {
            AppLogger.vault.debug("Lock Screen capture could not be stripped; discarded")
            return .unusable
        } catch {
            AppLogger.vault.debug("Lock Screen capture could not be sealed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }

        guard opensLockScreenCaptures, wipeEpoch == epoch, encryptionKey != nil, lockGeneration == generation else {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.encryptedFileName))
            AppLogger.security.debug("Lock Screen capture discarded: vault state changed while sealing")
            return .vaultClosed
        }
        guard !vaultedItems.contains(where: { $0.id == item.id }) else { return .alreadyStored }

        vaultedItems.append(item)
        guard saveVaultedItemsMetadataToDisk() else {
            vaultedItems.removeAll { $0.id == item.id }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(item.encryptedFileName))
            return .failed
        }
        AuditLogManager.shared.log(
            .photoCaptured,
            message: "Photo captured from the Lock Screen",
            metadata: ["photo_id": item.id.uuidString, "source": "lock_screen"]
        )
        return .stored
    }
}

extension MetadataPrivacyService {
    static func strippedImageData(from data: Data) -> Data? {
        MetadataStrip.strippedImageData(from: data)
    }
}
