// NuDefndr — nudefndr.com
// Transparency Repository - Subscription entitlements (v2.6.1)

import Foundation
import RevenueCat
import StoreKit // Needed for AppStore.sync()
import Combine
import OSLog // Use modern OSLog for better logging

@MainActor // Ensure UI updates happen on the main thread
class PurchaseManager: ObservableObject {
    // MARK: - Published Properties (for UI updates)
    @Published var offerings: Offerings? = nil
    @Published var customerInfo: CustomerInfo? = nil
    @Published var isProUser: Bool = false
    @Published var isLoading: Bool = false // To show activity indicators
    /// Errors from a *purchase or restore* the user explicitly started. Kept
    /// separate from `offeringsError` so a network blip while the price list
    /// loads can't surface as "Purchase Error" over a screen the user has
    /// only just opened.
    @Published var lastError: String? = nil
    /// Errors from fetching the price list. Drives the paywall's inline retry
    /// panel, never an alert.
    @Published var offeringsError: String? = nil
    /// Result of the most recent restore, for UI to report and then clear.
    /// Restore is the one action that can succeed while changing nothing
    /// visible, so "nothing happened" has to be sayable.
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

    // MARK: - Private Properties
    private var customerInfoStreamTask: Task<Void, Never>? = nil // Keep stream alive
    private var isConfigured: Bool = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "PurchaseManager")
    
    // --- Retry Logic Config ---
    private let maxFetchRetryAttempts = 3 // Max auto-retries for fetchOfferings
    private let initialRetryDelaySeconds: Double = 1.0
    private let maxRetryDelaySeconds: Double = 8.0 // Don't wait forever
    
    // MARK: - Initialization
    init() {
        // Start from the last entitlement RevenueCat actually confirmed, not
        // from `false`. Resolving the real answer is a network round trip, and
        // seeding pessimistically meant every paying customer saw a flash of
        // free-tier UI — locked settings, and their premium theme dropping to
        // Essential — on every cold launch.
        //
        // Optimistic only for display. `lastKnownProEntitlement` is ordinary
        // UserDefaults and therefore user-writable, so it must never be what
        // stands between someone and a paid feature.
        //
        // What actually makes that safe is structural, and worth stating
        // precisely: every UI surface that can reach a gated operation —
        // review/results (`addAssetsToVault`), the vault, the lock screen — is
        // behind `ContentView.hasInitiallyLoaded`, which is set only *after*
        // `configureAndFetch()` has written the receipt-backed value. The seed
        // cannot outlive the loading screen.
        //
        // So: if you add a gated action reachable before `hasInitiallyLoaded`
        // (a notification tap, a deep link, an App Intent), it must check
        // `isProUser` only after awaiting the real fetch — this seed will lie
        // to it.
        self.isProUser = ProEntitlementCache.isPro

        Task {
            await fetchInitialCustomerInfo()
        }
    }
    
    deinit {
        // Cancel the stream task when the manager is deallocated
        customerInfoStreamTask?.cancel()
    }
    
    // MARK: - Configuration (Call this explicitly, e.g., in app init or .task)
    func configureAndFetch() async {
        guard !isConfigured else {
            logger.info("Already configured. Refreshing data...")
            await fetchOfferingsAsyncWithRetry() // Just refresh offerings if already configured
            return
        }
        
        logger.info("Configuring RevenueCat SDK and fetching initial data...")
        // `Purchases.configure(withAPIKey:)` is called once, at app launch, in the
        // app's entry point rather than here — it is a single line taking the
        // public client key and no other options. Every other RevenueCat call the
        // app makes is in this file.
        
        isLoading = true // Set loading true for the entire initial sequence
        isConfigured = true
        lastError = nil
        
        // Fetch initial CustomerInfo first
        await fetchInitialCustomerInfo() // Await this helper
        
        // Start listening for real-time customer info updates
        listenForCustomerInfoUpdates()
        logger.info("Started listening for CustomerInfo updates.")
        
        // Now fetch offerings using the async method with retry
        await fetchOfferingsAsyncWithRetry() // Await this helper
        
        // isLoading state is managed within fetchOfferingsAsyncWithRetry now
        // It will be set to false when the fetch (including retries) completes or fails definitively.
        logger.info("Initial configuration and fetch process started (isLoading will be updated by fetchOfferings).")
        
        validateReceiptPath() // Optional diagnostic
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
    
    // MARK: - Data Fetching Helpers
    
    /// Fetches only the initial CustomerInfo.
    private func fetchInitialCustomerInfo() async {
        logger.info("Fetching initial CustomerInfo...")
        do {
            let info = try await Purchases.shared.customerInfo()
            handleCustomerInfoUpdate(info)
        } catch {
            logger.error("Error fetching initial CustomerInfo: \(error.localizedDescription)")
            lastError = "Could not fetch user data. \(error.localizedDescription)"
            // Consider if you want to stop the whole process if this fails
        }
        // configureAndFetch will call fetchOfferingsAsyncWithRetry after this returns.
    }
    
    /// Fetches Offerings using async/await with retry logic. Manages isLoading state.
    func fetchOfferingsAsyncWithRetry() async {
        // If called manually (e.g., retry button), ensure isLoading reflects this call
        if !isLoading { isLoading = true }
        offeringsError = nil
        var currentAttempt = 0 // Track attempts for this specific call sequence
        
        while currentAttempt <= maxFetchRetryAttempts {
            currentAttempt += 1
            logger.info(" Fetching offerings... (Attempt \(currentAttempt)/\(self.maxFetchRetryAttempts + 1))")
            
            do {
                let fetchedOfferings = try await Purchases.shared.offerings()
                // SUCCESS
                logger.info(" Offerings fetched successfully.")
                if offerings?.all.count != fetchedOfferings.all.count {
                    offerings = fetchedOfferings
                }
                // Clear the previous attempt's error. It is only reset at the
                // top of the function, so a failure followed by a successful
                // retry left `offeringsError` populated alongside a perfectly
                // good price list.
                offeringsError = nil
                if isLoading {
                    isLoading = false // Stop loading on success
                }
                return // Exit loop on success
                
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
                        guard self.isLoading else { // Check if loading was cancelled elsewhere
                            self.logger.info("Skipping retry as loading state changed.")
                            return false
                        }
                        return true
                    }.value
                    
                    guard retrySuccessful else {
                        logger.info("Retry cancelled or loading state changed, exiting fetch loop.")
                        if self.isLoading { self.isLoading = false } // Ensure loading is false
                        return
                    }
                    // Continue to the next iteration of the while loop
                } else {
                    logger.error("Fetch offerings failed definitively after \(currentAttempt) attempts or due to non-retryable error.")
                    if isLoading {
                        isLoading = false // Stop loading on definitive failure
                    }
                    return // Exit loop
                }
            } catch {
                logger.error(" Fetch offerings failed definitively after \(currentAttempt) attempts with non-RC error: \(error.localizedDescription)")
                offeringsError = error.localizedDescription
                if isLoading {
                    isLoading = false // Stop loading on definitive failure
                }
                return // Exit loop
            }
        }
        // If loop finishes without returning (max retries exceeded)
        logger.error("Fetch offerings failed after max (\(self.maxFetchRetryAttempts + 1)) attempts.")
        if isLoading { // Ensure loading is set false if loop completes due to retries
            isLoading = false
        }
    }
    
    // MARK: - Manual Actions (Retry / Reset)
    
    /// Called by the manual "Retry Loading" button
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
    
    /// Called by the manual "Reset Store Connection" button
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
    
    func purchase(package: Package) async { /* ... as before ... */
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
            // `.fetchCurrent` is implicit in restorePurchases — it posts the
            // receipt rather than reading the cache, so a stale "not pro"
            // cache cannot suppress a genuine entitlement.
            let info = try await Purchases.shared.restorePurchases()
            let restored = info.entitlements["pro"]?.isActive == true
            logger.info(" Restore completed. Pro entitlement active: \(restored)")
            // Set the outcome *before* publishing the new entitlement. The
            // paywall dismisses itself when `isProUser` flips, and it checks
            // `restoreOutcome` to decide whether to let the confirmation be
            // read first — so this has to be visible by then.
            restoreOutcome = restored ? .restored : .noPurchasesFound
            handleCustomerInfoUpdate(info)
            HapticManager.shared.notification(restored ? .success : .warning)
        } catch let rcError as RevenueCat.ErrorCode {
            logger.error(" Restore failed with RC ErrorCode: \(rcError.localizedDescription)")
            // A cancelled restore is not a failure worth reporting; anything
            // else is, and the user needs the reason to act on it — in words
            // they can act on, not "RevenueCat.ErrorCode error 8."
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
    
    // MARK: - Subscription Summary (for settings display)

    struct SubscriptionSummary {
        /// Short plan name, e.g. "LIFETIME", "ANNUAL", "MONTHLY", "PRO".
        let planLabel: String
        /// Renewal / expiry detail, e.g. "Renews 12 Mar 2027", "One-time purchase".
        let detail: String
    }

    /// Human-readable plan + renewal info for the active "pro" entitlement, or nil if not Pro.
    func proSubscriptionSummary() -> SubscriptionSummary? {
        guard let entitlement = customerInfo?.entitlements["pro"], entitlement.isActive else {
            return nil
        }

        // No expiration date => non-subscription (lifetime) purchase.
        guard let expiration = entitlement.expirationDate else {
            return SubscriptionSummary(planLabel: "LIFETIME", detail: "One-time purchase")
        }

        let dateString = expiration.formatted(date: .abbreviated, time: .omitted)
        let detail = entitlement.willRenew ? "Renews \(dateString)" : "Ends \(dateString)"
        return SubscriptionSummary(planLabel: planLabel(forProductID: entitlement.productIdentifier), detail: detail)
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

        // 2. Pro status
        let newIsPro = info.entitlements["pro"]?.isActive == true
        if newIsPro != isProUser {
            isProUser = newIsPro
        }
        // Verified answer — safe to cache for the next launch. Also what
        // demotes a lapsed subscriber's premium theme back to Essential.
        let entitlementChanged = ProEntitlementCache.isPro != newIsPro
        ProEntitlementCache.record(newIsPro)
        if entitlementChanged {
            // The widget renders the effective theme, so it has to be told when
            // the entitlement behind that theme changes — otherwise the home
            // screen keeps a premium palette the app has already dropped.
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
            // Already owned but the entitlement didn't come through — a restore
            // is the fix, so say so instead of showing a dead end.
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
                // Use fetchCurrent to bypass cache for this diagnostic
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
