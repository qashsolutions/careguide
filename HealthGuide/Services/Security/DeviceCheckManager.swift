//
//  DeviceCheckManager.swift
//  HealthGuide
//
//  Manages device-level tracking that survives app deletion
//  Uses Apple's DeviceCheck API to prevent reinstall abuse
//

import Foundation
import DeviceCheck
import CryptoKit
import UIKit

@available(iOS 18.0, *)
actor DeviceCheckManager {
    
    // MARK: - Singleton
    static let shared = DeviceCheckManager()
    
    // MARK: - Properties
    // Don't store DCDevice as it's not Sendable - access it on demand
    private let keychainService = KeychainService.shared
    private let backendURL = "https://hhprkmzegvegystnzehj.supabase.co/functions/v1"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhocHJrbXplZ3ZlZ3lzdG56ZWhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1NDEyMDYsImV4cCI6MjA3MDExNzIwNn0.5wCwaRw0iRxwKJgnyImYmdYnHyfwbku4mb2n6eH1Z5M"
    
    // Keychain keys
    private enum KeychainKeys {
        static let deviceID = "device_identifier"
        static let lastAccessDate = "last_access_date"
        static let originalTransactionID = "original_transaction_id"
        static let userFingerprint = "user_fingerprint"
    }
    
    // MARK: - Device Identification
    
    /// Get or create a permanent device ID that survives app deletion
    func getDeviceIdentifier() async -> String {
        // Use KeychainService convenience method
        let deviceId = await keychainService.getDeviceIdentifier()
        
        // Register with DeviceCheck if supported and new
        let isSupported = await MainActor.run { DCDevice.current.isSupported }
        if isSupported {
            await registerDeviceWithBackend(deviceID: deviceId)
        }
        
        return deviceId
    }
    
    /// Create a unique fingerprint for this user/device combination
    func getUserFingerprint() async -> String {
        let deviceID = await getDeviceIdentifier()
        let vendorID = await MainActor.run {
            UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        }
        let transactionID = (try? await keychainService.getString(for: KeychainKeys.originalTransactionID, service: .subscription)) ?? "none"
        
        // Combine multiple signals
        let combined = "\(deviceID)-\(vendorID)-\(transactionID)"
        
        // Create SHA256 hash for privacy
        let inputData = Data(combined.utf8)
        let hashed = SHA256.hash(data: inputData)
        let fingerprint = hashed.compactMap { String(format: "%02x", $0) }.joined()
        
        // Store in keychain
        try? await keychainService.setString(fingerprint, for: KeychainKeys.userFingerprint, service: .device)
        
        return fingerprint
    }
    
    // MARK: - Daily Access Tracking
    
    /// Check if daily access has been used (survives app deletion)
    func isDailyAccessUsed() async -> Bool {
        // 1. Check local Keychain first (fast)
        if let lastAccessDate = await keychainService.getLastAccessDate() {
            if Calendar.current.isDateInToday(lastAccessDate) {
                print("✅ Daily access already used (from Keychain)")
                return true
            }
        }
        
        // 2. Check with DeviceCheck API (survives reinstall)
        let isSupported = await MainActor.run { DCDevice.current.isSupported }
        if isSupported {
            return await checkDeviceAccessWithBackend()
        }
        
        return false
    }
    
    /// Mark daily access as used
    func markDailyAccessUsed() async {
        // 1. Store in Keychain
        await keychainService.setLastAccessDate(Date())
        
        // 2. Update DeviceCheck bits
        let isSupported = await MainActor.run { DCDevice.current.isSupported }
        if isSupported {
            await updateDeviceAccessWithBackend(used: true)
        }
        
        print("✅ Marked daily access as used")
    }
    
    /// Reset daily access at midnight
    func resetDailyAccessIfNeeded() async {
        if let lastAccessDate = await keychainService.getLastAccessDate(),
           !Calendar.current.isDateInToday(lastAccessDate) {
            
            // Reset DeviceCheck bits
            let isSupported = await MainActor.run { DCDevice.current.isSupported }
        if isSupported {
                await updateDeviceAccessWithBackend(used: false)
            }
            
            print("🔄 Reset daily access for new day")
        }
    }
    
    // MARK: - Subscription Tracking
    
    /// Store original transaction ID (links to Apple ID, survives reinstall)
    func storeOriginalTransactionID(_ transactionID: String) async {
        await keychainService.setOriginalTransactionId(transactionID)
        print("💳 Stored original transaction ID")
    }
    
    /// Get stored transaction ID
    func getOriginalTransactionID() async -> String? {
        return await keychainService.getOriginalTransactionId()
    }
    
    // MARK: - DeviceCheck API Integration
    
    /// Register device with backend using DeviceCheck token
    private func registerDeviceWithBackend(deviceID: String) async {
        let isSupported = await MainActor.run { DCDevice.current.isSupported }
        guard isSupported else {
            print("⚠️ DeviceCheck not supported on this device")
            return
        }
        
        do {
            // generateToken is already thread-safe, no need for MainActor
            let token = try await DCDevice.current.generateToken()
            
            // Send to Supabase backend
            var request = URLRequest(url: URL(string: "\(backendURL)/device-register")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let payload: [String: Any] = [
                "deviceToken": token.base64EncodedString(),
                "deviceID": deviceID,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("✅ Device registered with backend")
            }
        } catch {
            print("❌ Failed to register device: \(error)")
        }
    }
    
    /// Check daily access status with backend
    private func checkDeviceAccessWithBackend() async -> Bool {
        let isSupported = await MainActor.run { DCDevice.current.isSupported }
        guard isSupported else { return false }
        
        do {
            // generateToken is already thread-safe, no need for MainActor
            let token = try await DCDevice.current.generateToken()
            
            var request = URLRequest(url: URL(string: "\(backendURL)/device-check-access")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let payload: [String: Any] = [
                "deviceToken": token.base64EncodedString(),
                "date": ISO8601DateFormatter().string(from: Date())
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessUsed = json["accessUsed"] as? Bool {
                return accessUsed
            }
        } catch {
            print("❌ Failed to check device access: \(error)")
        }
        
        return false
    }
    
    /// Update daily access status with backend
    private func updateDeviceAccessWithBackend(used: Bool) async {
        let isSupported = await MainActor.run { DCDevice.current.isSupported }
        guard isSupported else { return }
        
        do {
            // generateToken is already thread-safe, no need for MainActor
            let token = try await DCDevice.current.generateToken()
            
            var request = URLRequest(url: URL(string: "\(backendURL)/device-update-access")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let payload: [String: Any] = [
                "deviceToken": token.base64EncodedString(),
                "accessUsed": used,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                print("✅ Device access updated with backend")
            }
        } catch {
            print("❌ Failed to update device access: \(error)")
        }
    }
    
    // MARK: - Group Admin Protection
    
    /// Check if user can become admin (must be member for 30+ days)
    func canBecomeGroupAdmin(joinDate: Date) -> Bool {
        let daysSinceJoining = Calendar.current.dateComponents([.day], from: joinDate, to: Date()).day ?? 0
        return daysSinceJoining >= 30
    }
    
    /// Validate device hasn't been used for multiple accounts
    func validateDeviceIntegrity() async -> Bool {
        let fingerprint = await getUserFingerprint()
        
        // Check with backend if this fingerprint is associated with multiple accounts
        var request = URLRequest(url: URL(string: "\(backendURL)/device-check-access")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let payload: [String: Any] = [
            "deviceToken": fingerprint,
            "date": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if device is banned or flagged
                if let isBanned = json["is_banned"] as? Bool, isBanned {
                    print("⚠️ Device flagged for multiple account usage")
                    return false
                }
            }
        } catch {
            print("❌ Failed to validate device integrity: \(error)")
        }
        
        print("✅ Device integrity validated with fingerprint: \(fingerprint.prefix(8))...")
        return true
    }
}

// MARK: - Supabase Backend Reference
/*
 Supabase Edge Functions:
 
 1. POST https://hhprkmzegvegystnzehj.supabase.co/functions/v1/device-register
    - Verify DeviceCheck token with Apple
    - Store device registration
 
 2. POST https://hhprkmzegvegystnzehj.supabase.co/functions/v1/device-check-access
    - Query DeviceCheck bits from Apple
    - Return if daily access was used
 
 3. POST https://hhprkmzegvegystnzehj.supabase.co/functions/v1/device-update-access
    - Update DeviceCheck bits via Apple API
    - Bit 0 = access used today
    - Bit 1 = subscription status
 
 Apple DeviceCheck Documentation:
 - https://developer.apple.com/documentation/devicecheck/
 */