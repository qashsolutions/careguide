//
//  UserSubscriptionTracker.swift
//  HealthGuide
//
//  Tracks user subscriptions and refund eligibility using payment info
//  Privacy-focused with hashed identifiers stored in Keychain
//

import Foundation
import CryptoKit
import Security

@available(iOS 18.0, *)
final class UserSubscriptionTracker {
    
    // MARK: - Singleton
    @MainActor static let shared = UserSubscriptionTracker()
    
    // MARK: - Constants
    private enum Constants {
        static let keychainService = "com.healthguide.subscription"
        static let userIdKey = "subscription.userId"
        static let emailKey = "subscription.email"
        static let phoneKey = "subscription.phone"
        static let refundHistoryKey = "subscription.refundHistory"
    }
    
    // MARK: - Refund Policy
    enum RefundPolicy {
        case firstTime   // 50% refund + 48 hours access
        case secondTime  // No refund + access until end of month
        case blocked     // Too many refunds, no longer eligible
        
        var refundPercentage: Double {
            switch self {
            case .firstTime: return 0.50
            case .secondTime, .blocked: return 0.0
            }
        }
        
        var accessDuration: AccessDuration {
            switch self {
            case .firstTime: return .hours(48)
            case .secondTime: return .untilEndOfBillingPeriod
            case .blocked: return .none
            }
        }
        
        var message: String {
            switch self {
            case .firstTime:
                return "First-time cancellation: You'll receive a 50% refund and have 48 hours to export your data."
            case .secondTime:
                return "You've used your one-time refund. You'll keep access until the end of your billing period with no refund."
            case .blocked:
                return "Due to previous refund history, you're no longer eligible for refunds."
            }
        }
    }
    
    enum AccessDuration {
        case hours(Int)
        case untilEndOfBillingPeriod
        case none
    }
    
    // MARK: - Models
    struct UserIdentity: Codable {
        let hashedId: String
        let email: String?
        let phone: String?
        let createdAt: Date
        let paymentMethod: String // "apple_pay" or "stripe"
        
        init(email: String? = nil, phone: String? = nil, paymentMethod: String) {
            // Create hashed ID from email or phone
            let identifier = email ?? phone ?? UUID().uuidString
            self.hashedId = UserSubscriptionTracker.hashIdentifier(identifier)
            self.email = email
            self.phone = phone
            self.createdAt = Date()
            self.paymentMethod = paymentMethod
        }
    }
    
    struct RefundRecord: Codable {
        let date: Date
        let amount: Decimal
        let reason: String
        let daysSinceSubscription: Int
    }
    
    struct SubscriptionHistory: Codable {
        let userId: String
        var refunds: [RefundRecord]
        var totalRefundCount: Int
        var lastSubscriptionDate: Date?
        var lastCancellationDate: Date?
        
        var isEligibleForRefund: Bool {
            return totalRefundCount == 0
        }
        
        var refundPolicy: RefundPolicy {
            switch totalRefundCount {
            case 0: return .firstTime
            case 1: return .secondTime
            default: return .blocked
            }
        }
    }
    
    // MARK: - Private Properties
    private let keychain = KeychainManager()
    
    // MARK: - Public Methods
    
    /// Store user identity from payment information
    func storeUserFromPayment(email: String? = nil, phone: String? = nil, paymentMethod: String) {
        let identity = UserIdentity(email: email, phone: phone, paymentMethod: paymentMethod)
        
        // Store in Keychain (survives app deletion)
        keychain.save(identity.hashedId, for: Constants.userIdKey)
        
        if let email = email {
            keychain.save(email, for: Constants.emailKey)
        }
        
        if let phone = phone {
            keychain.save(phone, for: Constants.phoneKey)
        }
        
        // Store identity data
        if let encoded = try? JSONEncoder().encode(identity) {
            keychain.saveData(encoded, for: "user.identity")
        }
        
        // Initialize subscription history if needed
        if getSubscriptionHistory() == nil {
            let history = SubscriptionHistory(
                userId: identity.hashedId,
                refunds: [],
                totalRefundCount: 0,
                lastSubscriptionDate: Date()
            )
            saveSubscriptionHistory(history)
        }
    }
    
    /// Get current user's subscription history
    func getSubscriptionHistory() -> SubscriptionHistory? {
        guard let userId = getCurrentUserId() else { return nil }
        
        if let data = keychain.loadData(for: "history.\(userId)"),
           let history = try? JSONDecoder().decode(SubscriptionHistory.self, from: data) {
            return history
        }
        
        return nil
    }
    
    /// Check refund eligibility for current user
    func checkRefundEligibility(daysSinceSubscription: Int) -> RefundPolicy {
        guard let history = getSubscriptionHistory() else {
            return .firstTime // New user
        }
        
        // Check if cancelling within refund window (days 8-14)
        guard daysSinceSubscription >= 8 && daysSinceSubscription <= 14 else {
            return .blocked // Outside refund window
        }
        
        // Check for subscription cycling abuse
        if let lastCancellation = history.lastCancellationDate {
            let daysSinceLastCancellation = Calendar.current.dateComponents(
                [.day], from: lastCancellation, to: Date()
            ).day ?? 0
            
            // If resubscribed within 60 days of last cancellation, no refund
            if daysSinceLastCancellation < 60 {
                return .blocked
            }
        }
        
        return history.refundPolicy
    }
    
    /// Process refund and update history
    func processRefund(amount: Decimal, daysSinceSubscription: Int) -> (refundAmount: Decimal, accessUntilDate: Date) {
        guard var history = getSubscriptionHistory() else {
            return (0, Date())
        }
        
        let policy = checkRefundEligibility(daysSinceSubscription: daysSinceSubscription)
        let refundAmount = amount * Decimal(policy.refundPercentage)
        
        // Calculate access end date
        let accessUntilDate: Date
        switch policy.accessDuration {
        case .hours(let hours):
            accessUntilDate = Calendar.current.date(byAdding: .hour, value: hours, to: Date()) ?? Date()
        case .untilEndOfBillingPeriod:
            accessUntilDate = Calendar.current.date(byAdding: .day, value: 31 - daysSinceSubscription, to: Date()) ?? Date()
        case .none:
            accessUntilDate = Date()
        }
        
        // Record refund if issued
        if refundAmount > 0 {
            let refundRecord = RefundRecord(
                date: Date(),
                amount: refundAmount,
                reason: "User requested cancellation",
                daysSinceSubscription: daysSinceSubscription
            )
            
            history.refunds.append(refundRecord)
            history.totalRefundCount += 1
        }
        
        history.lastCancellationDate = Date()
        saveSubscriptionHistory(history)
        
        return (refundAmount, accessUntilDate)
    }
    
    /// Record new subscription
    func recordNewSubscription() {
        guard var history = getSubscriptionHistory() else { return }
        
        history.lastSubscriptionDate = Date()
        saveSubscriptionHistory(history)
    }
    
    /// Get current user ID
    func getCurrentUserId() -> String? {
        return keychain.load(for: Constants.userIdKey)
    }
    
    /// Get user email (for receipts)
    func getUserEmail() -> String? {
        return keychain.load(for: Constants.emailKey)
    }
    
    // MARK: - Private Methods
    
    private func saveSubscriptionHistory(_ history: SubscriptionHistory) {
        if let encoded = try? JSONEncoder().encode(history) {
            keychain.saveData(encoded, for: "history.\(history.userId)")
        }
    }
    
    private static func hashIdentifier(_ identifier: String) -> String {
        let inputData = Data(identifier.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Keychain Manager
@available(iOS 18.0, *)
private class KeychainManager {
    
    private let service = "com.healthguide.subscription"
    
    func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(data, for: key)
    }
    
    func saveData(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        #if DEBUG
        if status != errSecSuccess {
            print("❌ Keychain save failed for key: \(key), status: \(status)")
        }
        #endif
    }
    
    func load(for key: String) -> String? {
        guard let data = loadData(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func loadData(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        
        return nil
    }
    
    func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
