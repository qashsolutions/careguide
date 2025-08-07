//
//  StripePaymentHandler.swift
//  HealthGuide
//
//  IMPORTANT: This file is DISABLED and not in use.
//  Apple requires In-App Purchases (StoreKit) for digital subscriptions in iOS apps.
//  
//  This Stripe implementation is preserved for future use cases:
//  - Web-based subscription portal
//  - Physical goods or services
//  - Donations or tips
//  - Services consumed outside the app
//
//  DO NOT use this for digital subscriptions within the iOS app - it will result in App Store rejection.
//  Current subscription implementation uses StoreKit (see SubscriptionManager.swift)
//

import Foundation

// MARK: - STRIPE CODE DISABLED - Using Apple IAP Instead
/*
 * This entire Stripe implementation is commented out because:
 * 1. Apple App Store Guidelines (3.1.1) require using In-App Purchases for digital content
 * 2. Using external payment processors for digital subscriptions will result in app rejection
 * 3. Stripe can only be used in iOS apps for:
 *    - Physical goods and services
 *    - Donations to recognized charities
 *    - Services consumed outside of the app
 * 
 * Our subscription (Careguide Premium) is a digital service, so we MUST use StoreKit.
 * This code remains here for potential future web implementation.
 */

/* STRIPE IMPLEMENTATION - DISABLED

@available(iOS 18.0, *)
actor StripePaymentHandler {
    
    // MARK: - Configuration
    private struct Configuration {
        // Load from Info.plist or environment
        static var publishableKey: String {
            // Only publishable key on client, secret key stays on server
            Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String ?? ""
        }
        
        static var backendBaseURL: String {
            #if DEBUG
            return "http://localhost:3000" // Your local server
            #else
            return "https://api.healthguide.com" // Your production server
            #endif
        }
    }
    
    // MARK: - Subscription Management
    
    struct StripeSubscription: Codable {
        let id: String
        let customerId: String
        let status: String
        let currentPeriodEnd: Date
        let cancelAtPeriodEnd: Bool
        
        var isActive: Bool {
            return status == "active" || status == "trialing"
        }
    }
    
    // MARK: - API Methods
    
    /// Create a new subscription with customer info
    func createSubscription(priceId: String, email: String, phone: String? = nil) async throws -> SubscriptionResponse {
        let endpoint = "\(Configuration.backendBaseURL)/api/subscriptions/create"
        
        let payload: [String: Any] = [
            "priceId": priceId,
            "email": email,  // Required for Stripe
            "phone": phone ?? "",  // Optional but recommended
            "trial_period_days": 7,
            "payment_behavior": "default_incomplete",
            "payment_method_options": [
                "card": [
                    "request_three_d_secure": "automatic"
                ]
            ],
            "metadata": [
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                "platform": "ios",
                "email": email,
                "phone": phone ?? ""
            ]
        ]
        
        let request = try createRequest(endpoint: endpoint, method: "POST", payload: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PaymentError.subscriptionCreationFailed
        }
        
        // Parse response and handle payment confirmation if needed
        let decoder = JSONDecoder()
        let subscriptionResponse = try decoder.decode(SubscriptionResponse.self, from: data)
        
        // Store user info for tracking
        await MainActor.run {
            UserSubscriptionTracker.shared.storeUserFromPayment(
                email: email,
                phone: phone,
                paymentMethod: "stripe"
            )
            UserSubscriptionTracker.shared.recordNewSubscription()
        }
        
        // Handle payment confirmation if needed
        if let clientSecret = subscriptionResponse.clientSecret {
            try await confirmPayment(clientSecret: clientSecret)
        }
        
        return subscriptionResponse
    }
    
    struct SubscriptionResponse: Codable {
        let subscriptionId: String
        let customerId: String
        let clientSecret: String?
        let status: String
    }
    
    /// Cancel subscription
    func cancelSubscription(subscriptionId: String) async throws {
        let endpoint = "\(Configuration.backendBaseURL)/api/subscriptions/\(subscriptionId)/cancel"
        
        let payload: [String: Any] = [
            "subscriptionId": subscriptionId,
            "cancel_at_period_end": false, // Immediate cancellation for refund
            "prorate": true
        ]
        
        let request = try createRequest(endpoint: endpoint, method: "POST", payload: payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PaymentError.cancellationFailed
        }
    }
    
    /// Get subscription status
    func getSubscriptionStatus(customerId: String) async throws -> StripeSubscription? {
        let endpoint = "\(Configuration.backendBaseURL)/api/subscriptions/status"
        
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "customerId", value: customerId)]
        
        let request = try createRequest(endpoint: components.url!.absoluteString, method: "GET", payload: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(StripeSubscription.self, from: data)
    }
    
    /// Process refund for early cancellation
    func processRefund(subscriptionId: String, amount: Decimal) async throws {
        let endpoint = "\(Configuration.backendBaseURL)/api/refunds/create"
        
        let payload: [String: Any] = [
            "subscriptionId": subscriptionId,
            "amount": NSDecimalNumber(decimal: amount * 100).intValue, // Convert to cents
            "reason": "requested_by_customer",
            "metadata": [
                "refund_type": "early_cancellation",
                "refund_percentage": "50"
            ]
        ]
        
        let request = try createRequest(endpoint: endpoint, method: "POST", payload: payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PaymentError.refundFailed
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func createRequest(endpoint: String, method: String, payload: [String: Any]?) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw PaymentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // API key authentication - the backend should validate requests using API keys
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        
        if let payload = payload {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        
        return request
    }
    
    private func confirmPayment(clientSecret: String) async throws {
        // Payment confirmation happens on the backend after webhook
        // The client secret is used by Stripe.js on web or Stripe SDK if you add it
        // Since we're using server-side confirmation, this is handled by webhook
        print("Payment will be confirmed via webhook with client secret: \(clientSecret)")
    }
}

// MARK: - Payment Errors

enum PaymentError: LocalizedError {
    case invalidURL
    case subscriptionCreationFailed
    case cancellationFailed
    case refundFailed
    case paymentConfirmationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .subscriptionCreationFailed:
            return "Failed to create subscription"
        case .cancellationFailed:
            return "Failed to cancel subscription"
        case .refundFailed:
            return "Failed to process refund"
        case .paymentConfirmationFailed:
            return "Payment confirmation failed"
        }
    }
}

*/ // END OF STRIPE IMPLEMENTATION - DISABLED