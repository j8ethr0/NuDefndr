// NuDefndr - nudefndr.com
// Transparency Repository - Pro entitlement cache (v2.6.3)

import Foundation

enum ProEntitlementCache {
    static var isPro: Bool {
        UserDefaults.standard.bool(forKey: AppKeys.lastKnownProEntitlement)
    }

    static func record(_ isPro: Bool) {
        guard UserDefaults.standard.bool(forKey: AppKeys.lastKnownProEntitlement) != isPro else { return }
        UserDefaults.standard.set(isPro, forKey: AppKeys.lastKnownProEntitlement)
        AppLogger.app.info("Pro entitlement cache updated: \(isPro, privacy: .public)")
    }

    static func effectiveTheme(forStored raw: String) -> AppTheme {
        let stored = AppTheme(rawValue: raw) ?? .essential
        guard stored.isPro else { return stored }
        return isPro ? stored : .essential
    }
}
