// NudeFndr - nudefndr.com
// Transparency Repository - Scan result model (v2.6.1)

// SensitiveAsset.swift
import Foundation
import Photos

/// Why an asset was flagged. Persisted as rawValue in the per-ID category
/// map; anything unknown/missing decodes as .nudity (all pre-2.7 data).
enum DetectionCategory: String, Codable, CaseIterable {
  case nudity
  case document
}

// Represents a detected sensitive asset
struct SensitiveAsset: Identifiable, Hashable {
  let id: String // PHAsset local identifier
  let asset: PHAsset // Keep the original asset reference
  let dateFound: Date
  let category: DetectionCategory

  var isNew: Bool {
      if let lastViewed = UserDefaults.standard.object(forKey: AppKeys.lastResultsViewedTimestamp) as? Date {
          return dateFound > lastViewed
      }
      return true
  }

  // Hashable conformance based on identifier
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
