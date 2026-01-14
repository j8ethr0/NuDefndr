// NudeFndr - nudefndr.com
// Transparency Repository

import Foundation

struct ScanResult {
	let isSensitive: Bool
	let timestamp: Date
	let assetIdentifier: String?
	
	init(isSensitive: Bool, assetIdentifier: String? = nil) {
		self.isSensitive = isSensitive
		self.timestamp = Date()
		self.assetIdentifier = assetIdentifier
	}
}