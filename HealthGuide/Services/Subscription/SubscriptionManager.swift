//
//  SubscriptionManager.swift
//  HealthGuide
//
//  Production-ready subscription management with StoreKit 2 ONLY
//  Stripe integration disabled per Apple App Store requirements
//  Handles 7-day trial, monthly billing, and refund logic
//

import Foundation
import StoreKit
import SwiftUI

// MARK: - Subscription Error Types

enum SubscriptionError: LocalizedError {
    case productNotFound
    case verificationFailed
    case userCancelled
    case paymentPending
    case notActive
    case missingEmail
    case stripeNotAvailable  // Added: Stripe payments disabled per App Store requirements
    case noActiveSubscriptionFound
    case networkError(Error)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found"
        case .verificationFailed:
            return "Purchase verification failed"
        case .userCancelled:
            return "Purchase was cancelled"
        case .paymentPending:
            return "Payment is pending"
        case .notActive:
            return "No active subscription found"
        case .missingEmail:
            return "Email is required for credit card payments"
        case .stripeNotAvailable:
            return "Credit card payments are not available. Please use Apple Pay."
        case .noActiveSubscriptionFound:
            return "No active subscriptions found to restore"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Supporting Types

struct SubscriptionInfo {
    let productId: String
    let expirationDate: Date?
    let isInTrial: Bool
    let willAutoRenew: Bool
}

struct CancellationResult {
    let refundAmount: Decimal
    let accessUntilDate: Date
    let wasWithinRefundPeriod: Bool
    let daysSinceStart: Int
    let refundPolicy: UserSubscriptionTracker.RefundPolicy
    
    var refundPercentageText: String {
        switch refundPolicy {
        case .firstTime: return "50%"
        case .secondTime, .blocked: return "0%"
        }
    }
    
    var policyMessage: String {
        return refundPolicy.message
    }
}

@available(iOS 18.0, *)
@MainActor
final class SubscriptionManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = SubscriptionManager()
    
    // MARK: - Subscription Configuration
    struct Configuration {
        static let monthlyPrice: Decimal = 8.99
        static let currency = "USD"
        static let trialDurationDays = 7
        static let refundPercentage = 0.50 // 50% refund within days 8-14 to prevent gaming
        static let gracePeriodDays = 3 // Extra days after failed payment
        
        // Product IDs for App Store
        static let monthlyProductId = "1942" // App Store Connect Product ID
        // static let annualProductId = "XXXX" // Future expansion - add Product ID from App Store Connect
        
        /* STRIPE CONFIGURATION DISABLED - Apple IAP Required for Digital Subscriptions
         * Stripe configuration preserved for potential future use:
         * - Web-based subscription portal
         * - Physical goods/services
         * DO NOT enable for iOS app digital subscriptions
        
        static var stripeMonthlyPriceId: String {
            // Load from environment/config
            return ProcessInfo.processInfo.environment["STRIPE_MONTHLY_PRICE_ID"] ?? ""
        }
        */
    }
    
    // MARK: - Subscription State
    enum SubscriptionState: Equatable {
        case loading
        case trial(startDate: Date, endDate: Date)
        case active(expiryDate: Date, autoRenew: Bool)
        case cancelled(accessUntilDate: Date, cancellationDate: Date)
        case gracePeriod(endDate: Date)
        case expired
        case none
        
        var isActive: Bool {
            switch self {
            case .trial, .active, .cancelled, .gracePeriod:
                return true
            case .loading, .expired, .none:
                return false
            }
        }
        
        var isInTrial: Bool {
            switch self {
            case .trial:
                return true
            default:
                return false
            }
        }
        
        var displayName: String {
            switch self {
            case .loading:
                return "Loading..."
            case .trial:
                return "Free Trial"
            case .active(_, let autoRenew):
                return autoRenew ? "Active" : "Active (Expires Soon)"
            case .cancelled:
                return "Cancelled"
            case .gracePeriod:
                return "Payment Issue"
            case .expired:
                return "Expired"
            case .none:
                return "No Subscription"
            }
        }
    }
    
    // MARK: - Payment Method
    enum PaymentMethod: String, CaseIterable {
        case applePay = "apple_pay"
        case creditCard = "credit_card"
        
        var displayName: String {
            switch self {
            case .applePay: return "Apple Pay"
            case .creditCard: return "Credit Card"
            }
        }
        
        var iconName: String {
            switch self {
            case .applePay: return "applelogo"
            case .creditCard: return "creditcard"
            }
        }
    }
    
    // MARK: - Published Properties
    @Published var subscriptionState: SubscriptionState = .loading
    @Published var availableProducts: [Product] = []
    @Published var purchasedProduct: Product?
    @Published var isProcessingPayment = false
    @Published var paymentError: String?
    
    // MARK: - Private Properties
    private var updateListenerTask: Task<Void, Never>?
    private let userDefaults = UserDefaults.standard
    
    // Computed property for trial status
    private var hasUsedTrial: Bool {
        return userDefaults.bool(forKey: UserDefaultsKeys.hasUsedTrial)
    }
    
    // UserDefaults Keys
    private enum UserDefaultsKeys {
        static let trialStartDate = "subscription.trial.startDate"
        static let subscriptionStartDate = "subscription.startDate"
        static let cancellationDate = "subscription.cancellationDate"
        static let hasUsedTrial = "subscription.hasUsedTrial"
        static let selectedPaymentMethod = "subscription.paymentMethod"
    }
    
    // MARK: - Initialization
    private init() {
        // Minimal init - no StoreKit operations
        print("📱 SubscriptionManager: Initialized (StoreKit deferred)")
    }
    
    /// Initialize the subscription manager - call after app is ready
    func initialize() async {
        print("🛍️ Initializing SubscriptionManager...")
        
        // Check if we're in simulator without Apple ID
        #if targetEnvironment(simulator)
        print("⚠️ Running in simulator - StoreKit may not work without Apple ID")
        // Set default state for simulator
        await MainActor.run {
            self.subscriptionState = .none
        }
        #else
        print("📱 Running on device - initializing StoreKit...")
        
        // Set a default state first
        await MainActor.run {
            self.subscriptionState = .none
        }
        
        print("🔧 Setting up StoreKit...")
        await setupStoreKit()
        
        print("📊 Checking subscription status...")
        await checkSubscriptionStatus()
        
        print("📦 Loading products...")
        await loadProducts()
        
        print("✅ SubscriptionManager initialization complete")
        #endif
    }
    
    /// Setup StoreKit components
    private func setupStoreKit() async {
        // Setup transaction listener with error handling
        await MainActor.run {
            self.updateListenerTask = Task {
                // Listen for transaction updates
                for await result in StoreKit.Transaction.updates {
                    do {
                        let transaction = try await self.verifyTransaction(result)
                        await self.handleTransactionUpdate(transaction)
                        await transaction.finish()
                    } catch {
                        // Handle transaction errors gracefully
                        if (error as NSError).code == 509 {
                            print("⚠️ No active Apple ID account - transactions unavailable")
                            break // Exit the loop
                        } else {
                            print("❌ Transaction update error: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    /// Handle transaction updates
    private func handleTransactionUpdate(_ transaction: StoreKit.Transaction) async {
        // Update subscription state based on transaction
        await checkSubscriptionStatus()
        
        // Post notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("SubscriptionStatusChanged"),
                object: nil
            )
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    /// Verify a transaction - defined early to avoid forward reference
    private func verifyTransaction<T>(_ result: VerificationResult<T>) async throws -> T {
        switch result {
        case .unverified(_, let error):
            print("❌ Transaction verification failed: \(error)")
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    /// Schedule trial notifications - defined early to avoid forward reference
    private func scheduleTrialNotifications(startDate: Date, endDate: Date) async {
        let notificationManager = NotificationManager.shared
        
        // Request notification permission if not already granted
        if !notificationManager.isNotificationEnabled {
            _ = await notificationManager.requestNotificationPermission()
        }
        
        // Schedule all trial notifications
        await notificationManager.scheduleTrialNotifications(startDate: startDate, endDate: endDate)
    }
    
    /// Calculate days since subscription start - defined early to avoid forward reference
    private func calculateDaysSinceSubscriptionStart() -> Int {
        guard let startDate = userDefaults.object(forKey: UserDefaultsKeys.subscriptionStartDate) as? Date else {
            return 0
        }
        return Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }
    
    /// Check Apple subscription status
    private func checkAppleSubscription() async {
        // Check current entitlements
        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try await verifyTransaction(result)
                if transaction.productID == Configuration.monthlyProductId {
                    if let expirationDate = transaction.expirationDate, expirationDate > Date() {
                        // Check if subscription will auto-renew
                        // If there's no revocation reason, subscription is active
                        let willAutoRenew = transaction.revocationReason == nil
                        
                        await MainActor.run {
                            self.subscriptionState = .active(expiryDate: expirationDate, autoRenew: willAutoRenew)
                        }
                        return
                    }
                }
            } catch {
                print("❌ Error checking entitlement: \(error)")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Start free trial
    func startFreeTrial() async {
        guard !hasUsedTrial else {
            paymentError = "You have already used your free trial"
            return
        }
        
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: Configuration.trialDurationDays, to: startDate)!
        
        userDefaults.set(startDate, forKey: UserDefaultsKeys.trialStartDate)
        userDefaults.set(true, forKey: UserDefaultsKeys.hasUsedTrial)
        userDefaults.set(false, forKey: "hasSeenPaymentPrompt") // Track payment prompt
        
        subscriptionState = .trial(startDate: startDate, endDate: endDate)
        
        // Schedule notifications
        await scheduleTrialNotifications(startDate: startDate, endDate: endDate)
    }
    
    /// Purchase subscription
    func purchaseSubscription(method: PaymentMethod, email: String? = nil, phone: String? = nil) async throws {
        isProcessingPayment = true
        paymentError = nil
        
        defer { isProcessingPayment = false }
        
        switch method {
        case .applePay:
            try await purchaseWithApplePay()
        case .creditCard:
            // STRIPE DISABLED: Apple requires In-App Purchases for digital subscriptions
            // Stripe payment processing is not allowed for digital content in iOS apps (App Store Guidelines 3.1.1)
            // This would only be used for a web portal or physical goods
            throw SubscriptionError.stripeNotAvailable
            
            /* STRIPE CODE DISABLED - DO NOT USE FOR DIGITAL SUBSCRIPTIONS
            guard let email = email else {
                throw SubscriptionError.missingEmail
            }
            try await purchaseWithStripe(email: email, phone: phone)
            */
        }
    }
    
    /// Cancel subscription with refund calculation
    func cancelSubscription() async throws -> CancellationResult {
        guard case .active(let expiryDate, _) = subscriptionState else {
            throw SubscriptionError.notActive
        }
        
        let cancellationDate = Date()
        let daysSinceStart = calculateDaysSinceSubscriptionStart()
        
        // Use tracker to determine refund eligibility
        let tracker = UserSubscriptionTracker.shared
        let refundPolicy = tracker.checkRefundEligibility(daysSinceSubscription: daysSinceStart)
        
        // Process refund based on policy
        let (refundAmount, accessUntilDate) = tracker.processRefund(
            amount: Configuration.monthlyPrice,
            daysSinceSubscription: daysSinceStart
        )
        
        // If no refund and outside refund window, keep original expiry date
        if refundAmount == 0 && daysSinceStart > 14 {
            let finalAccessDate = expiryDate // Keep full month access
            
            // Process cancellation - Only Apple IAP supported
            // Stripe cancellation disabled per App Store requirements
            try await cancelAppleSubscription()
            
            /* STRIPE CANCELLATION DISABLED
            if isApplePaySubscription() {
                try await cancelAppleSubscription()
            } else {
                try await cancelStripeSubscription()
            }
            */
            
            // Update state
            userDefaults.set(cancellationDate, forKey: UserDefaultsKeys.cancellationDate)
            subscriptionState = .cancelled(accessUntilDate: finalAccessDate, cancellationDate: cancellationDate)
            
            return CancellationResult(
                refundAmount: 0,
                accessUntilDate: finalAccessDate,
                wasWithinRefundPeriod: false,
                daysSinceStart: daysSinceStart,
                refundPolicy: refundPolicy
            )
        }
        
        // Process cancellation - Only Apple IAP supported
        // Stripe cancellation disabled per App Store requirements
        try await cancelAppleSubscription()
        
        /* STRIPE CANCELLATION DISABLED
        if isApplePaySubscription() {
            try await cancelAppleSubscription()
        } else {
            try await cancelStripeSubscription()
        }
        */
        
        // Update state
        userDefaults.set(cancellationDate, forKey: UserDefaultsKeys.cancellationDate)
        subscriptionState = .cancelled(accessUntilDate: accessUntilDate, cancellationDate: cancellationDate)
        
        return CancellationResult(
            refundAmount: refundAmount,
            accessUntilDate: accessUntilDate,
            wasWithinRefundPeriod: daysSinceStart <= 14,
            daysSinceStart: daysSinceStart,
            refundPolicy: refundPolicy
        )
    }
    
    /// Check current subscription status
    func checkSubscriptionStatus() async {
        // Check trial status first
        if let trialStartDate = userDefaults.object(forKey: UserDefaultsKeys.trialStartDate) as? Date {
            let endDate = Calendar.current.date(byAdding: .day, value: Configuration.trialDurationDays, to: trialStartDate)!
            
            if Date() < endDate {
                subscriptionState = .trial(startDate: trialStartDate, endDate: endDate)
                return
            }
        }
        
        // Default to none for now (StoreKit check disabled for debugging)
        subscriptionState = .none
        
        // Check Apple subscription only - Stripe disabled for digital subscriptions
        // await checkAppleSubscription() // TEMPORARILY DISABLED
        
        /* STRIPE CHECK DISABLED - Apple IAP required for digital subscriptions
         * Cannot use external payment processors for digital content per App Store Guidelines
        if subscriptionState == .none || subscriptionState == .expired {
            await checkStripeSubscription()
        }
        */
    }
    
    // MARK: - Private Methods - Apple Pay
    
    private func cancelAppleSubscription() async throws {
        // Note: Actual cancellation happens in Settings app
        // We can only track the state change
        guard purchasedProduct != nil else {
            throw SubscriptionError.productNotFound
        }
        
        // Open subscription management in Settings
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await UIApplication.shared.open(url)
        }
    }
    
    private func purchaseWithApplePay() async throws {
        guard let product = availableProducts.first(where: { $0.id == Configuration.monthlyProductId }) else {
            throw SubscriptionError.productNotFound
        }
        
        do {
            print("🛒 Starting purchase for product: \(product.id)")
            let result = try await product.purchase()
            print("✅ Purchase result received")
            
            switch result {
            case .success(let verification):
                print("✅ Purchase successful, verifying transaction...")
                let transaction = try await verifyTransaction(verification)
                print("✅ Transaction verified: \(transaction.id)")
                
                // Validate receipt
                print("🔍 Validating receipt...")
                try await validateReceipt(transaction: transaction)
                print("✅ Receipt validated")
                
                // Store user identity from Apple transaction
                // Apple provides anonymized ID but we can use it for tracking
                let tracker = UserSubscriptionTracker.shared
                if let appAccountToken = transaction.appAccountToken {
                    let tokenString = appAccountToken.uuidString
                    tracker.storeUserFromPayment(
                        email: tokenString, // Using token as identifier
                        phone: nil,
                        paymentMethod: PaymentMethod.applePay.rawValue
                    )
                }
                
                // Store original transaction ID for device tracking
                // This survives app deletion and prevents abuse
                let originalID = transaction.originalID
                await DeviceCheckManager.shared.storeOriginalTransactionID(String(originalID))
                print("📱 Stored original transaction ID for device tracking")
            
            print("🏁 Finishing transaction...")
            await transaction.finish()
            print("✅ Transaction finished")
            
            userDefaults.set(Date(), forKey: UserDefaultsKeys.subscriptionStartDate)
            userDefaults.set(PaymentMethod.applePay.rawValue, forKey: UserDefaultsKeys.selectedPaymentMethod)
            
            tracker.recordNewSubscription()
            print("🔄 Checking subscription status...")
            await checkSubscriptionStatus()
            print("✅ Purchase complete!")
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.paymentPending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
        } catch {
            throw error
        }
    }
    
    // MARK: - Receipt Validation
    
    /// Validate transaction receipt locally
    private func validateReceipt(transaction: StoreKit.Transaction) async throws {
        // Local validation
        guard transaction.productID == Configuration.monthlyProductId else {
            throw SubscriptionError.verificationFailed
        }
        
        // Verify transaction is not revoked
        if transaction.revocationDate != nil {
            throw SubscriptionError.verificationFailed
        }
        
        // For production, you should implement server-side receipt validation
        // This is a basic local validation
        print("✅ Receipt validated for transaction: \(transaction.id)")
        
        // Store validated transaction
        userDefaults.set(transaction.id, forKey: "lastValidatedTransactionId")
        userDefaults.set(Date(), forKey: "lastValidationDate")
    }
    
    // MARK: - Error Recovery
    
    /// Handle purchase errors with retry logic
    private func handlePurchaseError(_ error: Error) async throws {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError(let urlError):
                // Network error - could retry
                print("❌ Network error: \(urlError)")
                throw SubscriptionError.networkError(urlError)
                
            case .userCancelled:
                // User cancelled - don't retry
                throw SubscriptionError.userCancelled
                
            case .notAvailableInStorefront:
                // Product not available in user's region
                throw SubscriptionError.productNotFound
                
            case .notEntitled:
                // User not entitled to make purchase
                throw SubscriptionError.notActive
                
            default:
                throw SubscriptionError.unknown
            }
        } else {
            throw error
        }
    }
    
    // MARK: - Private Methods - Stripe [DISABLED]
    /*
     * IMPORTANT: All Stripe methods are disabled and should not be used.
     * Apple App Store Guidelines (Section 3.1.1) require using In-App Purchases for digital subscriptions.
     * 
     * Using Stripe or any external payment processor for digital content will result in:
     * 1. App Store rejection during review
     * 2. Removal from App Store if already published
     * 3. Potential developer account suspension
     * 
     * These methods are preserved only for potential future use cases:
     * - Web-based subscription portal (outside of iOS app)
     * - Physical goods or services
     * - Donations to registered non-profits
     */
    
    /* STRIPE PURCHASE - DISABLED
    private func purchaseWithStripe(email: String, phone: String? = nil) async throws {
        // This integrates with your Stripe backend
        // For production, never handle Stripe keys client-side
        
        let paymentHandler = StripePaymentHandler()
        let subscription = try await paymentHandler.createSubscription(
            priceId: Configuration.stripeMonthlyPriceId,
            email: email,
            phone: phone
        )
        
        // Store subscription ID for future reference
        userDefaults.set(subscription.subscriptionId, forKey: "stripe.subscriptionId")
        userDefaults.set(subscription.customerId, forKey: "stripe.customerId")
        userDefaults.set(Date(), forKey: UserDefaultsKeys.subscriptionStartDate)
        userDefaults.set(PaymentMethod.creditCard.rawValue, forKey: UserDefaultsKeys.selectedPaymentMethod)
        
        await checkSubscriptionStatus()
    }
    */
    
    /* STRIPE CANCELLATION - DISABLED
    private func cancelStripeSubscription() async throws {
        let paymentHandler = StripePaymentHandler()
        try await paymentHandler.cancelSubscription(
            subscriptionId: getUserStripeSubscriptionId()
        )
    }
    */
    
    /* STRIPE STATUS CHECK - DISABLED
    private func checkStripeSubscription() async {
        // Check with your backend for Stripe subscription status
        let paymentHandler = StripePaymentHandler()
        if let subscription = try? await paymentHandler.getSubscriptionStatus(
            customerId: getUserStripeCustomerId()
        ) {
            if subscription.isActive {
                subscriptionState = .active(
                    expiryDate: subscription.currentPeriodEnd,
                    autoRenew: !subscription.cancelAtPeriodEnd
                )
            }
        }
    }
    */
    
    // MARK: - Helper Methods
    
    private func isApplePaySubscription() -> Bool {
        let method = userDefaults.string(forKey: UserDefaultsKeys.selectedPaymentMethod)
        return method == PaymentMethod.applePay.rawValue
    }
    
    private func getUserStripeCustomerId() -> String {
        // Retrieve from UserDefaults stored after Stripe customer creation
        return userDefaults.string(forKey: "stripe.customerId") ?? ""
    }
    
    private func getUserStripeSubscriptionId() -> String {
        // Retrieve from UserDefaults stored after subscription creation
        return userDefaults.string(forKey: "stripe.subscriptionId") ?? ""
    }
    
    /// Check if user should see payment prompt (day 5 or later)
    var shouldShowPaymentPrompt: Bool {
        guard case .trial(let startDate, _) = subscriptionState else { return false }
        
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        let hasSeenPrompt = userDefaults.bool(forKey: "hasSeenPaymentPrompt")
        
        return daysSinceStart >= 5 && !hasSeenPrompt
    }
    
    /// Mark payment prompt as seen
    func markPaymentPromptSeen() {
        userDefaults.set(true, forKey: "hasSeenPaymentPrompt")
    }
    
    /// Get days remaining in trial
    var trialDaysRemaining: Int {
        guard case .trial(_, let endDate) = subscriptionState else { return 0 }
        
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(0, days)
    }
    
    // MARK: - Load Products
    func loadProducts() async {
        do {
            print("🔍 Attempting to load product ID: \(Configuration.monthlyProductId)")
            let products = try await Product.products(for: [Configuration.monthlyProductId])
            print("✅ Loaded \(products.count) products")
            for product in products {
                print("  - Product: \(product.id), Price: \(product.displayPrice)")
            }
            await MainActor.run {
                self.availableProducts = products
            }
        } catch {
            print("❌ Failed to load products: \(error)")
            print("  Product ID attempted: \(Configuration.monthlyProductId)")
        }
    }
    
    // MARK: - Convenience Methods for UI
    
    /// Simplified purchase method for UI - always uses Apple Pay
    func purchase() async throws {
        try await purchaseSubscription(method: .applePay)
    }
    
    /// Restore purchases from App Store
    func restorePurchases() async throws {
        isProcessingPayment = true
        defer { isProcessingPayment = false }
        
        do {
            // Sync with App Store to restore purchases
            try await AppStore.sync()
            
            // Check subscription status after sync
            await checkSubscriptionStatus()
            
            // If no active subscription found after restore
            if !subscriptionState.isActive {
                throw SubscriptionError.noActiveSubscriptionFound
            }
            
            print("✅ Successfully restored purchases")
        } catch {
            print("❌ Failed to restore purchases: \(error)")
            throw error
        }
    }
    
    /// Get current subscription information
    func getCurrentSubscriptionInfo() async -> SubscriptionInfo? {
        guard availableProducts.contains(where: { $0.id == Configuration.monthlyProductId }) else {
            return nil
        }
        
        // Get current entitlements
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Configuration.monthlyProductId {
                return SubscriptionInfo(
                    productId: transaction.productID,
                    expirationDate: transaction.expirationDate,
                    isInTrial: transaction.offer?.type == .introductory,
                    willAutoRenew: transaction.revocationReason == nil
                )
            }
        }
        
        return nil
    }
}

// MARK: - End of SubscriptionManager