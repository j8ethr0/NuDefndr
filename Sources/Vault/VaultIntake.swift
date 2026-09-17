// NuDefndr - nudefndr.com
// Transparency Repository - Vault intake: metadata strip, seal and write (v2.6.3)

import Foundation
import CryptoKit
import ImageIO
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
                                                  originalAssetIdentifier: String?) throws -> VaultItem {
        guard let cleanData = MetadataPrivacyService.strippedImageData(from: imageData)
                ?? UIImage(data: imageData)?.jpegData(compressionQuality: 0.95) else {
            throw VaultIntakeError.metadataStripFailed
        }
        let sealedBox = try ChaChaPoly.seal(cleanData, using: key)

        let newItemID = UUID()
        let encryptedFileName = "\(newItemID.uuidString).encrypteddata"
        let fileURL = vaultDir.appendingPathComponent(encryptedFileName)
        do {
            try sealedBox.combined.write(to: fileURL, options: [.completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw error
        }

        return VaultItem(id: newItemID,
                         encryptedFileName: encryptedFileName,
                         originalAssetIdentifier: originalAssetIdentifier,
                         dateAdded: Date())
    }
}

extension MetadataPrivacyService {
    static func strippedImageData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }

        let count = CGImageSourceGetCount(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, count, nil) else { return nil }

        for index in 0..<count {
            var removal: [CFString: Any] = [
                kCGImagePropertyGPSDictionary: kCFNull as Any,
                kCGImagePropertyExifDictionary: kCFNull as Any,
                kCGImagePropertyExifAuxDictionary: kCFNull as Any,
                kCGImagePropertyTIFFDictionary: kCFNull as Any,
                kCGImagePropertyIPTCDictionary: kCFNull as Any,
                kCGImagePropertyMakerAppleDictionary: kCFNull as Any
            ]
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let orientation = properties[kCGImagePropertyOrientation] {
                removal[kCGImagePropertyOrientation] = orientation
            }
            CGImageDestinationAddImageFromSource(destination, source, index, removal as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
