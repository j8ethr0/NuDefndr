// NuDefndr - nudefndr.com
// Transparency Repository - Scan result model (v2.6.3)

import Foundation
import Photos

enum DetectionCategory: String, Codable, CaseIterable {
  case nudity
  case document
}

struct SensitiveAsset: Identifiable, Hashable {
  let id: String
  let asset: PHAsset
  let dateFound: Date
  let category: DetectionCategory

  var isNew: Bool {
      if let lastViewed = UserDefaults.standard.object(forKey: AppKeys.lastResultsViewedTimestamp) as? Date {
          return dateFound > lastViewed
      }
      return true
  }

  func hash(into hasher: inout Hasher) {
      hasher.combine(id)
  }

  static func == (lhs: SensitiveAsset, rhs: SensitiveAsset) -> Bool {
      lhs.id == rhs.id
  }

  init(id: String, asset: PHAsset, dateFound: Date = Date(), category: DetectionCategory = .nudity) {
      self.id = id
      self.asset = asset
      self.dateFound = dateFound
      self.category = category
  }
}
