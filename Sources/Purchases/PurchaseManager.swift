// NuDefndr - nudefndr.com
// Transparency Repository - Subscription entitlements (v2.6.3)

import Foundation
import RevenueCat
import StoreKit
import Combine
import OSLog

@MainActor
class PurchaseManager: ObservableObject {
    @Published var offerings: Offerings? = nil
    @Published var customerInfo: CustomerInfo? = nil
    @Published var isProUser: Bool = false
    @Published var isLoading: Bool = false
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

    private var customerInfoStreamTask: Task<Void, Never>? = nil
    private var isConfigured: Bool = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PurchaseManager")

    private let maxFetchRetryAttempts = 3
    private let initialRetryDelaySeconds: Double = 1.0
    private let maxRetryDelaySeconds: Double = 8.0

    init() {
        self.isProUser = ProEntitlementCache.isPro

        Task {
            await fetchInitialCustomerInfo()
        }
    }

    deinit {
        customerInfoStreamTask?.cancel()
    }

    func configureAndFetch() async {
        guard !isConfigured else {
            logger.info("Already configured. Refreshing data...")
            await fetchOfferingsAsyncWithRetry()
            return
        }

        logger.info("Configuring RevenueCat SDK and fetching initial data...")

        isLoading = true
        isConfigured = true
        lastError = nil

        await fetchInitialCustomerInfo()

        listenForCustomerInfoUpdates()
        logger.info("Started listening for CustomerInfo updates.")

        await fetchOfferingsAsyncWithRetry()

        logger.info("Initial configuration and fetch process started (isLoading will be updated by fetchOfferings).")

        validateReceiptPath()
    }

    private func listenForCustomerInfoUpdates() {
        customerInfoStreamTask?.cancel()
        customerInfoStreamTask = Task { [weak self] in
            let stream = Purchases.shared.customerInfoStream
            for await info in stream {
                guard !Task.isCancelled else { break }
                self?.logger.info("Received update from customerInfoStream.")
                self?.handleCustomerInfoUpdate(info)
            }
            self?.logger.info("CustomerInfo stream listener finished.")
        }
    }

    private func fetchInitialCustomerInfo() async {
        logger.info("Fetching initial CustomerInfo...")
        do {
            let info = try await Purchases.shared.customerInfo()
            handleCustomerInfoUpdate(info)
        } catch {
            logger.error("Error fetching initial CustomerInfo: \(error.localizedDescription)")
            lastError = "Could not fetch user data. \(error.localizedDescription)"
        }
    }

    func fetchOfferingsAsyncWithRetry() async {
        if !isLoading { isLoading = true }
        offeringsError = nil
        var currentAttempt = 0

        while currentAttempt <= maxFetchRetryAttempts {
            currentAttempt += 1
            logger.info(" Fetching offerings... (Attempt \(currentAttempt)/\(self.maxFetchRetryAttempts + 1))")

            do {
                let fetchedOfferings = try await Purchases.shared.offerings()
                logger.info(" Offerings fetched successfully.")
                if offerings?.all.count != fetchedOfferings.all.count {
                    offerings = fetchedOfferings
                }
                offeringsError = nil
                if isLoading {
                    isLoading = false
                }
                return
            } catch let rcError as RevenueCat.ErrorCode {
                logger.error(" Error fetching offerings (Attempt \(currentAttempt)): RC Code \(rcError) - \(rcError.localizedDescription)")
                offeringsError = rcError.localizedDescription

                let isRetryableError = rcError == .networkError ||
                rcError == .offlineConnectionError ||
                rcError == .configurationError ||
                rcError == .unexpectedBackendResponseError

                if isRetryableError && currentAttempt <= self.maxFetchRetryAttempts {
                    let delaySeconds = min(maxRetryDelaySeconds, pow(2.0, Double(currentAttempt - 1)) * initialRetryDelaySeconds)
                    let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
                    logger.warning(" Retrying fetch after \(delaySeconds)s delay...")

                    let retrySuccessful = await Task { () -> Bool in
                        try? await Task.sleep(nanoseconds: delayNanoseconds)
                        guard self.isLoading else {
                            self.logger.info("Skipping retry as loading state changed.")
                            return false
                        }
                        return true
                    }.value

                    guard retrySuccessful else {
                        logger.info("Retry cancelled or loading state changed, exiting fetch loop.")
                        if self.isLoading { self.isLoading = false }
                        return
                    }
                } else {
                    logger.error("Fetch offerings failed definitively after \(currentAttempt) attempts or due to non-retryable error.")
                    if isLoading {
                        isLoading = false
                    }
                    return
                }
            } catch {
                logger.error(" Fetch offerings failed definitively after \(currentAttempt) attempts with non-RC error: \(error.localizedDescription)")
                offeringsError = error.localizedDescription
                if isLoading {
                    isLoading = false
                }
                return
            }
        }
        logger.error("Fetch offerings failed after max (\(self.maxFetchRetryAttempts + 1)) attempts.")
        if isLoading {
            isLoading = false
        }
    }

    func retryFetchingOfferings() {
        logger.info("Manual retry tapped.")
        guard !isLoading else {
            logger.info("Manual retry skipped, already loading.")
            return
        }
        Task {
            await fetchOfferingsAsyncWithRetry()
        }
    }

    func resetStoreConnectionAndFetch() async {
        logger.info(" Resetting store connection...")
        isLoading = true
        lastError = nil

        logger.debug("Attempting AppStore.sync()...")
        do {
            try await AppStore.sync()
            logger.info(" AppStore.sync() completed successfully.")
        } catch {
            logger.warning(" AppStore.sync() failed: \(error.localizedDescription)")
        }

        Purchases.shared.invalidateCustomerInfoCache()
        logger.info("RC CustomerInfo cache invalidated.")

        logger.info("Triggering fetchOfferings after reset.")
        await self.fetchOfferingsAsyncWithRetry()
    }

    func purchase(package: Package) async {
        guard !isLoading else { logger.warning("Purchase skipped, already processing."); return }
        isLoading = true
        lastError = nil
        logger.info(" Starting purchase for package: \(package.identifier)...")
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if let transaction = result.transaction {
                logger.info(" Purchase successful for product: \(transaction.productIdentifier)")
            } else {
                logger.info(" Purchase/Restore process completed via RC. Transaction details may arrive via listener.")
            }
            handleCustomerInfoUpdate(result.customerInfo)
            logger.info("Purchase check completed. isProUser: \(self.isProUser)")
        } catch let rcError as RevenueCat.ErrorCode { handlePurchaseError(rcError); logger.error(" Purchase failed with RC ErrorCode: \(rcError.localizedDescription)") }
        catch { lastError = error.localizedDescription; logger.error(" Purchase failed with generic error: \(error.localizedDescription)") }
        isLoading = false
    }

    func restorePurchases() async {
        guard !isLoading else { logger.warning("Restore skipped, already processing."); return }
        isLoading = true
        lastError = nil
        restoreOutcome = nil
        logger.info(" Restoring purchases...")
        do {
            let info = try await Purchases.shared.restorePurchases()
            let restored = info.entitlements["pro"]?.isActive == true
            logger.info(" Restore completed. Pro entitlement active: \(restored)")
            restoreOutcome = restored ? .restored : .noPurchasesFound
            handleCustomerInfoUpdate(info)
            HapticManager.shared.notification(restored ? .success : .warning)
        } catch let rcError as RevenueCat.ErrorCode {
            logger.error(" Restore failed with RC ErrorCode: \(rcError.localizedDescription)")
            if rcError == .purchaseCancelledError {
                restoreOutcome = nil
            } else {
                restoreOutcome = .failed(friendlyMessage(for: rcError, restoring: true))
                HapticManager.shared.notification(.error)
            }
        } catch {
            logger.error(" Restore failed with generic error: \(error.localizedDescription)")
            restoreOutcome = .failed(error.localizedDescription)
            HapticManager.shared.notification(.error)
        }
        isLoading = false
    }

    struct SubscriptionSummary {
        let planLabel: String
        let detail: String
    }

    func proSubscriptionSummary() -> SubscriptionSummary? {
        guard let info = customerInfo,
              let entitlement = info.entitlements["pro"], entitlement.isActive else {
            return nil
        }

        if ownsLifetime(info) {
            return SubscriptionSummary(planLabel: "LIFETIME",
                                       detail: String(localized: "SETTINGS_PLAN_LIFETIME_DETAIL",
                                                      defaultValue: "One-time purchase"))
        }

        guard let expiration = entitlement.expirationDate else {
            return SubscriptionSummary(planLabel: "LIFETIME",
                                       detail: String(localized: "SETTINGS_PLAN_LIFETIME_DETAIL",
                                                      defaultValue: "One-time purchase"))
        }

        let dateString = expiration.formatted(date: .abbreviated, time: .omitted)
        let detail = entitlement.willRenew
            ? String(format: String(localized: "SETTINGS_PLAN_RENEWS",
                                    defaultValue: "Renews %@"), dateString)
            : String(format: String(localized: "SETTINGS_PLAN_ENDS",
                                    defaultValue: "Ends %@"), dateString)
        return SubscriptionSummary(planLabel: planLabel(forProductID: entitlement.productIdentifier), detail: detail)
    }

    private func ownsLifetime(_ info: CustomerInfo) -> Bool {
        if info.nonSubscriptions.contains(where: { $0.productIdentifier.lowercased().contains("lifetime") }) {
            return true
        }
        return info.allPurchasedProductIdentifiers.contains { $0.lowercased().contains("lifetime") }
    }

    private func planLabel(forProductID id: String) -> String {
        let lower = id.lowercased()
        if lower.contains("annual") || lower.contains("year") { return "ANNUAL" }
        if lower.contains("month") { return "MONTHLY" }
        if lower.contains("week") { return "WEEKLY" }
        return "PRO"
    }

    private func handleCustomerInfoUpdate(_ info: CustomerInfo) {
        customerInfo = info

        let newIsPro = info.entitlements["pro"]?.isActive == true
        if newIsPro != isProUser {
            isProUser = newIsPro
        }
        let entitlementChanged = ProEntitlementCache.isPro != newIsPro
        ProEntitlementCache.record(newIsPro)
        if entitlementChanged {
            ProtectionWidgetData.sync()
        }

        logger.info(" CustomerInfo processed. isProUser: \(newIsPro)")
        if !info.entitlements.active.isEmpty {
            logger.debug("Active entitlements: \(info.entitlements.active.keys.joined(separator: ", "))")
        }
    }
    private func handlePurchaseError(_ error: RevenueCat.ErrorCode) {
        if error == .purchaseCancelledError {
            logger.info(" User cancelled the purchase.")
            lastError = nil
            return
        }
        lastError = friendlyMessage(for: error, restoring: false)
    }

    private func friendlyMessage(for error: RevenueCat.ErrorCode, restoring: Bool) -> String {
        switch error {
        case .paymentPendingError:
            logger.warning(" Purchase is pending (e.g., Ask to Buy).")
            return String(localized: "PURCHASE_ERROR_PENDING",
                          defaultValue: "Payment is awaiting approval. Your purchase will unlock automatically once it is approved.")
        case .purchaseNotAllowedError:
            return String(localized: "PURCHASE_ERROR_NOT_ALLOWED",
                          defaultValue: "Purchases are not allowed on this device. Check Screen Time restrictions in Settings.")
        case .productAlreadyPurchasedError:
            return String(localized: "PURCHASE_ERROR_ALREADY_OWNED",
                          defaultValue: "You already own this. Tap Restore Purchases to unlock it.")
        case .invalidReceiptError, .missingReceiptFileError:
            return restoring
                ? String(localized: "RESTORE_ERROR_NO_RECEIPT",
                         defaultValue: "No purchase record was found on this device. Make sure you are signed in to the App Store with the Apple Account you bought with.")
                : String(localized: "PURCHASE_ERROR_RECEIPT",
                         defaultValue: "The App Store could not confirm this purchase. Make sure you are signed in to the App Store and try again.")
        case .receiptAlreadyInUseError, .receiptInUseByOtherSubscriberError:
            return String(localized: "RESTORE_ERROR_RECEIPT_IN_USE",
                          defaultValue: "That purchase is already linked to a different account. Contact support and we will sort it out.")
        case .networkError, .offlineConnectionError:
            return String(localized: "PURCHASE_ERROR_NETWORK",
                          defaultValue: "No connection to the App Store. Check your network and try again.")
        case .storeProblemError, .unknownBackendError, .unexpectedBackendResponseError:
            return String(localized: "PURCHASE_ERROR_STORE",
                          defaultValue: "The App Store is not responding. Please try again shortly.")
        case .invalidCredentialsError, .configurationError:
            return String(localized: "PURCHASE_ERROR_CONFIG",
                          defaultValue: "The store is temporarily unavailable. Please try again later.")
        default:
            logger.error(" Unmapped RC error code: \(error) - \(error.localizedDescription)")
            return String(localized: "PURCHASE_ERROR_GENERIC",
                          defaultValue: "Something went wrong talking to the App Store. Please try again.")
        }
    }
    private func validateReceiptPath() {
        Task {
            logger.debug("Performing diagnostic receipt validation check...")
            do {
                let info = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
                logger.info(" Diagnostic receipt validation successful. Active entitlements: \(info.entitlements.active.count)")
            } catch {
                logger.warning(" Diagnostic receipt validation check failed: \(error.localizedDescription)")
                if let rcError = error as? RevenueCat.ErrorCode,
                   rcError == .receiptAlreadyInUseError || rcError == .invalidReceiptError {
                    logger.error(" Possible persistent receipt validation path issue detected.")
                }
            }
        }
    }
}
