// NuDefndr — nudefndr.com
// Transparency Repository - Pro entitlement cache (v2.6.1)

import Foundation

/// The last Pro entitlement state confirmed by a real CustomerInfo response.
///
/// `PurchaseManager.isProUser` starts `false` on every cold launch and only
/// becomes true once RevenueCat answers — a network round trip. Anything that
/// reads entitlement during that window sees "free", so a paying customer gets
/// a flash of free-tier UI on every single launch.
///
/// This caches the answer so the app can start from the truth it already knew
/// and correct itself a moment later, instead of starting from a lie.
///
/// Deliberately plain UserDefaults with no RevenueCat import: it is read from
/// theme resolution on the launch path, and needs to stay usable from targets
/// that do not link the SDK.
///
/// This is a *display* signal, not an authorization one. It is user-writable
/// like any UserDefaults value, so it must never gate a purchase, an unlock, or
/// anything else of value — `PurchaseManager.isProUser`, backed by a verified
/// receipt, remains the only thing allowed to do that. All this decides is
/// whether to show someone their own theme for the second before the real
/// answer arrives.
enum ProEntitlementCache {
    static var isPro: Bool {
        UserDefaults.standard.bool(forKey: AppKeys.lastKnownProEntitlement)
    }

    static func record(_ isPro: Bool) {
        guard UserDefaults.standard.bool(forKey: AppKeys.lastKnownProEntitlement) != isPro else { return }
        UserDefaults.standard.set(isPro, forKey: AppKeys.lastKnownProEntitlement)
        AppLogger.app.info("Pro entitlement cache updated: \(isPro, privacy: .public)")
    }

    /// The theme to actually render.
    ///
    /// Premium themes are a paid feature, but `selectedAppTheme` is ordinary
    /// persisted storage with nothing watching it — so a lapsed subscriber kept
    /// their paid theme indefinitely, which is the one Pro feature that carried
    /// on working after the entitlement died.
    ///
    /// Resolved at the point of read rather than by rewriting the stored value,
    /// the same way `TravelMode` layers its overrides. Two reasons: re-subscribing
    /// silently restores the theme the user chose, and a transient "not Pro"
    /// answer can never destroy a preference we would be unable to recover.
    static func effectiveTheme(forStored raw: String) -> AppTheme {
        let stored = AppTheme(rawValue: raw) ?? .essential
        guard stored.isPro else { return stored }
        return isPro ? stored : .essential
    }
}
