// NuDefndr - nudefndr.com
// Transparency Repository - Subscription entitlements (v2.6.8)

import Foundation
import StoreKit
import Combine
import OSLog
import UIKit

@MainActor
class PurchaseManager: ObservableObject {
    enum ProductID {
        static let monthly = "com.dro1d.nudefndr.monthly"
        static let annual = "com.dro1d.nudefndr.annual"
        static let lifetime = "com.dro1d.nudefndr.lifetime"
        static let all = [monthly, annual, lifetime]
        static let subscriptionGroupID = "21677352"
    }

    @Published var products: [Product] = []
    @Published var introOfferEligibility: [String: Bool] = [:]
    @Published var isProUser: Bool = false
    @Published var isLifetimeOwner: Bool = false
    @Published var isLoading: Bool = false
    @Published var isFetchingProducts: Bool = false
    @Published var pendingNotice: String? = nil
    @Published var lastError: String? = nil
    @Published var offeringsError: String? = nil
    @Published var restoreOutcome: RestoreOutcome? = nil

    enum RestoreOutcome: Equatable {
        case restored
        case noPurchasesFound
        case failed(String)

        var alertTitle: String {
            switch self {
            case .restored:
                return String(localized: "PAYWALL_RESTORE_SUCCESS_TITLE", defaultValue: "Purchase Restored")
            case .noPurchasesFound:
                return String(localized: "PAYWALL_RESTORE_NONE_TITLE", defaultValue: "Nothing to Restore")
            case .failed:
                return String(localized: "PAYWALL_RESTORE_FAILED_TITLE", defaultValue: "Restore Failed")
            }
        }

        var alertMessage: String {
            switch self {
            case .restored:
                return String(localized: "PAYWALL_RESTORE_SUCCESS_BODY",
                              defaultValue: "Your purchase is active. Everything is unlocked.")
            case .noPurchasesFound:
                return String(localized: "PAYWALL_RESTORE_NONE_BODY",
                              defaultValue: "No previous purchase was found on this Apple Account. If you bought NUDEFNDR with a different Apple Account, sign in with that one in Settings and try again.")
            case .failed(let reason):
                return reason
            }
        }
    }

    struct EntitlementSnapshot: Equatable {
        var ownsLifetime = false
        var subscriptionProductID: String? = nil
        var subscriptionExpiration: Date? = nil
        var willRenew = false

        var isPro: Bool { ownsLifetime || subscriptionProductID != nil }
    }

    @Published private(set) var entitlements: EntitlementSnapshot? = nil

    private var transactionUpdatesTask: Task<Void, Never>? = nil
    private var isConfigured: Bool = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PurchaseManager")

    private let maxFetchRetryAttempts = 3
    private let initialRetryDelaySeconds: Double = 1.0
    private let maxRetryDelaySeconds: Double = 8.0

    init() {
        self.isProUser = ProEntitlementCache.isPro
        self.isLifetimeOwner = UserDefaults.standard.bool(forKey: AppKeys.lastKnownLifetimeEntitlement)

        listenForTransactionUpdates()

        Task {
            await refreshEntitlements()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func configureAndFetch() async {
        guard !isConfigured else {
            if products.isEmpty { await fetchProductsWithRetry() }
            return
        }

        logger.info("Configuring StoreKit and fetching initial data...")
        isConfigured = true
        lastError = nil

        await finishOutstandingTransactions()
        await refreshEntitlements()

        Task { await fetchProductsWithRetry() }
        logger.info("Initial configuration complete; price list loading.")
    }

    private func listenForTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                switch result {
                case .verified(let transaction):
                    self.logger.info("Transaction update: \(transaction.productID, privacy: .public) (\(String(describing: transaction.productType), privacy: .public))")
                    await transaction.finish()
                case .unverified(let transaction, let error):
                    self.logger.error("Unverified transaction update for \(transaction.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                await self.refreshEntitlements()
            }
            self?.logger.info("Transaction update listener finished.")
        }
    }

    private func finishOutstandingTransactions() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                logger.info("Finishing outstanding transaction for \(transaction.productID, privacy: .public)")
                await transaction.finish()
            }
        }
    }

    func refreshEntitlements() async {
        let snapshot = await readEntitlements()
        guard await mayDemote(given: snapshot, authoritative: false) else { return }
        applyEntitlements(snapshot)
    }

    private static let emptyReadsKey = "proEntitlementEmptyReads"

    private func mayDemote(given snapshot: EntitlementSnapshot, authoritative: Bool) async -> Bool {
        let defaults = UserDefaults.standard
        guard !snapshot.isPro, ProEntitlementCache.isPro else {
            defaults.removeObject(forKey: Self.emptyReadsKey)
            return true
        }
        let app = UIApplication.shared
        guard app.isProtectedDataAvailable, app.applicationState != .background else {
            logger.info("Empty entitlement read while not in front; keeping the last verified answer.")
            return false
        }
        if Self.installRanRevenueCat, !(await Self.hasAnyTransaction()) {
            logger.notice("Pro with no App Store transaction on a RevenueCat install: carrying the entitlement over.")
            return false
        }
        if authoritative { return true }
        let emptyReads = defaults.integer(forKey: Self.emptyReadsKey) + 1
        defaults.set(emptyReads, forKey: Self.emptyReadsKey)
        guard emptyReads >= 2 else {
            logger.notice("First empty entitlement read for a Pro account; keeping Pro until the App Store confirms it.")
            return false
        }
        return true
    }

    private static var installRanRevenueCat: Bool {
        UserDefaults.standard.dictionaryRepresentation().keys.contains { $0.hasPrefix("com.revenuecat.") }
    }

    private static func hasAnyTransaction() async -> Bool {
        for await _ in Transaction.all { return true }
        return false
    }

    func sceneDidBecomeActive() {
        guard isConfigured else { return }
        Task { await refreshEntitlements() }
    }

    private func readEntitlements() async -> EntitlementSnapshot {
        var snapshot = EntitlementSnapshot()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                logger.warning("Skipping unverified entitlement.")
                continue
            }
            if transaction.revocationDate != nil { continue }

            switch transaction.productType {
            case .nonConsumable:
                if transaction.productID == ProductID.lifetime
                    || transaction.productID.lowercased().contains("lifetime") {
                    snapshot.ownsLifetime = true
                }
            case .autoRenewable:
                let current = snapshot.subscriptionExpiration ?? .distantPast
                if (transaction.expirationDate ?? .distantFuture) >= current {
                    snapshot.subscriptionProductID = transaction.productID
                    snapshot.subscriptionExpiration = transaction.expirationDate
                }
            default:
                break
            }
        }

        if snapshot.subscriptionProductID != nil {
            snapshot.willRenew = await subscriptionWillRenew(for: snapshot.subscriptionProductID)
        }
        return snapshot
    }

    private func subscriptionWillRenew(for productID: String?) async -> Bool {
        do {
            let statuses: [Product.SubscriptionInfo.Status]
            if let product = products.first(where: { $0.id == productID }), let info = product.subscription {
                statuses = try await info.status
            } else {
                statuses = try await Product.SubscriptionInfo.status(for: ProductID.subscriptionGroupID)
            }
            for status in statuses {
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    if case .verified(let renewal) = status.renewalInfo {
                        return renewal.willAutoRenew
                    }
                default:
                    continue
                }
            }
        } catch {
            logger.warning("Could not read subscription status: \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    private func applyEntitlements(_ snapshot: EntitlementSnapshot) {
        entitlements = snapshot

        let newIsPro = snapshot.isPro
        if newIsPro != isProUser {
            isProUser = newIsPro
        }
        let entitlementChanged = ProEntitlementCache.isPro != newIsPro
        ProEntitlementCache.record(newIsPro)
        if entitlementChanged {
            ProtectionWidgetData.sync()
        }

        let newIsLifetime = snapshot.ownsLifetime
        if newIsLifetime != isLifetimeOwner { isLifetimeOwner = newIsLifetime }
        UserDefaults.standard.set(newIsLifetime, forKey: AppKeys.lastKnownLifetimeEntitlement)

        logger.info(" Entitlements processed. isProUser: \(newIsPro), isLifetimeOwner: \(newIsLifetime), subscription: \(snapshot.subscriptionProductID ?? "none", privacy: .public)")
    }

    func fetchProductsWithRetry() async {
        guard !isFetchingProducts else { return }
        isFetchingProducts = true
        defer { isFetchingProducts = false }
        offeringsError = nil
        var currentAttempt = 0

        while currentAttempt <= maxFetchRetryAttempts {
            currentAttempt += 1
            logger.info(" Fetching products... (Attempt \(currentAttempt)/\(self.maxFetchRetryAttempts + 1))")

            do {
                let fetched = try await Product.products(for: ProductID.all)
                let ordered = ProductID.all.compactMap { id in fetched.first { $0.id == id } }
                logger.info(" Products fetched successfully: \(ordered.map(\.id).joined(separator: ", "), privacy: .public)")

                if ordered.isEmpty {
                    offeringsError = String(localized: "PURCHASE_ERROR_CONFIG",
                                            defaultValue: "The store is temporarily unavailable. Please try again later.")
                    return
                }

                if products.map(\.id) != ordered.map(\.id) {
                    products = ordered
                }
                introOfferEligibility = await introOfferEligibility(for: ordered)
                offeringsError = nil
                return
            } catch {
                logger.error(" Error fetching products (Attempt \(currentAttempt)): \(error.localizedDescription, privacy: .public)")
                offeringsError = friendlyMessage(for: error, restoring: false)

                if isRetryable(error) && currentAttempt <= self.maxFetchRetryAttempts {
                    let delaySeconds = min(maxRetryDelaySeconds, pow(2.0, Double(currentAttempt - 1)) * initialRetryDelaySeconds)
                    logger.warning(" Retrying fetch after \(delaySeconds)s delay...")
                    try? await Task.sleep(for: .seconds(delaySeconds))
                } else {
                    logger.error("Fetch products failed definitively after \(currentAttempt) attempts or due to non-retryable error.")
                    return
                }
            }
        }
        logger.error("Fetch products failed after max (\(self.maxFetchRetryAttempts + 1)) attempts.")
    }

    private func introOfferEligibility(for products: [Product]) async -> [String: Bool] {
        var eligibility: [String: Bool] = [:]
        for product in products {
            guard let subscription = product.subscription, subscription.introductoryOffer != nil else { continue }
            eligibility[product.id] = await subscription.isEligibleForIntroOffer
        }
        return eligibility
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError, .systemError, .unknown:
                return true
            default:
                return false
            }
        }
        return (error as NSError).domain == NSURLErrorDomain
    }

    func retryFetchingOfferings() {
        logger.info("Manual retry tapped.")
        guard !isFetchingProducts else {
            logger.info("Manual retry skipped, already loading.")
            return
        }
        Task {
            await fetchProductsWithRetry()
        }
    }

    func purchase(product: Product) async {
        guard !isLoading else { logger.warning("Purchase skipped, already processing."); return }
        isLoading = true
        lastError = nil
        logger.info(" Starting purchase for product: \(product.id, privacy: .public)...")
        do {
            let result: Product.PurchaseResult
            if let scene = Self.activeScene {
                result = try await product.purchase(confirmIn: scene)
            } else {
                result = try await product.purchase()
            }
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    logger.info(" Purchase successful for product: \(transaction.productID, privacy: .public)")
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified(let transaction, let error):
                    logger.error(" Purchase of \(transaction.productID, privacy: .public) could not be verified: \(error.localizedDescription, privacy: .public)")
                    lastError = String(localized: "PURCHASE_ERROR_RECEIPT",
                                       defaultValue: "The App Store could not confirm this purchase. Make sure you are signed in to the App Store and try again.")
                }
            case .pending:
                logger.warning(" Purchase is pending (e.g., Ask to Buy).")
                pendingNotice = String(localized: "PURCHASE_ERROR_PENDING",
                                       defaultValue: "Payment is awaiting approval. Your purchase will unlock automatically once it is approved.")
            case .userCancelled:
                logger.info(" User cancelled the purchase.")
                lastError = nil
            @unknown default:
                logger.warning(" Purchase returned an unknown result.")
            }
            logger.info("Purchase check completed. isProUser: \(self.isProUser)")
        } catch {
            handlePurchaseError(error)
        }
        isLoading = false
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    func restorePurchases() async {
        guard !isLoading else { logger.warning("Restore skipped, already processing."); return }
        isLoading = true
        lastError = nil
        restoreOutcome = nil
        logger.info(" Restoring purchases...")
        do {
            try await AppStore.sync()

            let snapshot = await readEntitlements()
            let restored = snapshot.isPro
            logger.info(" Restore completed. Pro entitlement active: \(restored)")
            restoreOutcome = restored ? .restored : .noPurchasesFound
            if await mayDemote(given: snapshot, authoritative: true) {
                applyEntitlements(snapshot)
            }
            HapticManager.shared.notification(restored ? .success : .warning)
        } catch {
            logger.error(" Restore failed: \(error.localizedDescription, privacy: .public)")
            if isCancellation(error) {
                restoreOutcome = nil
            } else {
                restoreOutcome = .failed(friendlyMessage(for: error, restoring: true))
                HapticManager.shared.notification(.error)
            }
        }
        isLoading = false
    }

    struct SubscriptionSummary {
        let planLabel: String
        let detail: String
    }

    func proSubscriptionSummary() -> SubscriptionSummary? {
        guard let snapshot = entitlements, snapshot.isPro else {
            return nil
        }

        if snapshot.ownsLifetime {
            return SubscriptionSummary(planLabel: String(localized: "PLAN_NAME_LIFETIME"),
                                       detail: String(localized: "SETTINGS_PLAN_LIFETIME_DETAIL",
                                                      defaultValue: "One-time purchase"))
        }

        guard let productID = snapshot.subscriptionProductID,
              let expiration = snapshot.subscriptionExpiration else {
            return SubscriptionSummary(planLabel: String(localized: "PLAN_NAME_LIFETIME"),
                                       detail: String(localized: "SETTINGS_PLAN_LIFETIME_DETAIL",
                                                      defaultValue: "One-time purchase"))
        }

        let dateString = expiration.formatted(date: .abbreviated, time: .omitted)
        let detail = snapshot.willRenew
            ? String(format: String(localized: "SETTINGS_PLAN_RENEWS",
                                    defaultValue: "Renews %@"), dateString)
            : String(format: String(localized: "SETTINGS_PLAN_ENDS",
                                    defaultValue: "Ends %@"), dateString)
        return SubscriptionSummary(planLabel: planLabel(forProductID: productID), detail: detail)
    }

    private func planLabel(forProductID id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("annual") || lower.contains("year") { return String(localized: "PLAN_NAME_ANNUAL", defaultValue: "ANNUAL") }
        if lower.contains("month") { return String(localized: "PLAN_NAME_MONTHLY", defaultValue: "MONTHLY") }
        if lower.contains("week") { return String(localized: "PLAN_NAME_WEEKLY", defaultValue: "WEEKLY", comment: "Subscription plan name shown in Settings") }
        return "PRO"
    }

    private func handlePurchaseError(_ error: Error) {
        if isCancellation(error) {
            logger.info(" User cancelled the purchase.")
            lastError = nil
            return
        }
        logger.error(" Purchase failed: \(error.localizedDescription, privacy: .public)")
        lastError = friendlyMessage(for: error, restoring: false)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError { return true }
        return error is CancellationError
    }

    private func friendlyMessage(for error: Error, restoring: Bool) -> String {
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .purchaseNotAllowed:
                return String(localized: "PURCHASE_ERROR_NOT_ALLOWED",
                              defaultValue: "Purchases are not allowed on this device. Check Screen Time restrictions in Settings.")
            case .productUnavailable, .invalidQuantity, .ineligibleForOffer,
                 .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature, .missingOfferParameters:
                return String(localized: "PURCHASE_ERROR_CONFIG",
                              defaultValue: "The store is temporarily unavailable. Please try again later.")
            default:
                break
            }
        }

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return String(localized: "PURCHASE_ERROR_NETWORK",
                              defaultValue: "No connection to the App Store. Check your network and try again.")
            case .systemError, .unknown:
                return String(localized: "PURCHASE_ERROR_STORE",
                              defaultValue: "The App Store is not responding. Please try again shortly.")
            case .notAvailableInStorefront, .unsupported:
                return String(localized: "PURCHASE_ERROR_CONFIG",
                              defaultValue: "The store is temporarily unavailable. Please try again later.")
            case .notEntitled:
                return restoring
                    ? String(localized: "RESTORE_ERROR_NO_RECEIPT",
                             defaultValue: "No purchase record was found on this device. Make sure you are signed in to the App Store with the Apple Account you bought with.")
                    : String(localized: "PURCHASE_ERROR_RECEIPT",
                             defaultValue: "The App Store could not confirm this purchase. Make sure you are signed in to the App Store and try again.")
            case .userCancelled:
                return ""
            default:
                break
            }
        }

        if (error as NSError).domain == NSURLErrorDomain {
            return String(localized: "PURCHASE_ERROR_NETWORK",
                          defaultValue: "No connection to the App Store. Check your network and try again.")
        }

        logger.error(" Unmapped StoreKit error: \(String(describing: error), privacy: .public)")
        return String(localized: "PURCHASE_ERROR_GENERIC",
                      defaultValue: "Something went wrong talking to the App Store. Please try again.")
    }
}
