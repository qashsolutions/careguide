//
//  TrialPersistenceManager.swift
//  HealthGuide
//
//  Manages trial state persistence across app deletions
//  Uses Keychain for local storage and Supabase for verification
//

import Foundation
import CryptoKit
import UIKit

@available(iOS 18.0, *)
@MainActor
final class TrialPersistenceManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = TrialPersistenceManager()
    
    // MARK: - Published Properties
    @Published var trialState: TrialState?
    @Published var isVerifying = false
    @Published var lastSyncError: Error?
    
    // MARK: - Private Properties
    private let keychainService = KeychainService.shared
    private let networkManager = NetworkManager.shared
    private let deviceCheckManager = DeviceCheckManager.shared
    
    // Keychain keys for trial persistence
    private enum TrialKeys {
        static let deviceId = "trial_device_id"
        static let trialData = "trial_persistent_data"
        static let verificationHash = "trial_verification_hash"
        static let service = KeychainService.Service.device // Use device service for max persistence
    }
    
    // Secret salt for hash generation (should be in secure config)
    private let hashSalt = "HG2024Trial$ecure$alt"
    
    // MARK: - Trial State Model (Simplified)
    struct TrialState: Codable, Sendable {
        let deviceId: UUID
        let trialStartDate: Date
        let trialExpiryDate: Date
        var lastPromptShownDate: Date?
        let appVersion: String
        
        // Simple 14-day trial
        static let trialDurationDays = 14
        
        var isValid: Bool {
            return Date() < trialExpiryDate
        }
        
        var daysRemaining: Int {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: Date(), to: trialExpiryDate).day ?? 0
            return max(0, days)
        }
        
        var daysUsed: Int {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
            return days
        }
        
        var isExpired: Bool {
            return Date() >= trialExpiryDate
        }
        
        var shouldShowPaymentModal: Bool {
            // Show on days 12 and 13
            let daysUsed = self.daysUsed
            return daysUsed >= 11 && daysUsed <= 12 && !isExpired
        }
        
        var requiresPayment: Bool {
            // Day 14+ requires payment
            return isExpired
        }
    }
    
    // MARK: - API Response Types (Sendable)
    
    struct TrialStartResponse: Codable, Sendable {
        let success: Bool
        let message: String?
    }
    
    struct TrialVerifyResponse: Codable, Sendable {
        let valid: Bool
        let trial_state: TrialStateResponse?
    }
    
    struct TrialStateResponse: Codable, Sendable {
        let started_at: String
        let expires_at: String
        let sessions_used: Int
        let sessions_remaining: Int
        let sessions_total: Int?
    }
    
    struct TrialSessionResponse: Codable, Sendable {
        let success: Bool
        let sessions_remaining: Int
    }
    
    // MARK: - Initialization
    private init() {
        print("🔐 TrialPersistenceManager: Initialized")
    }
    
    // MARK: - Public Methods
    
    /// Initialize and verify trial state on app launch
    func initialize() async {
        print("🎫 Initializing trial persistence...")
        
        // Try to load existing trial from Keychain
        if let existingTrial = await loadTrialFromKeychain() {
            print("🎫 Found existing trial in Keychain")
            
            // Verify integrity
            if await verifyTrialIntegrity(existingTrial) {
                self.trialState = existingTrial
                
                // Sync with backend (non-blocking)
                Task {
                    await syncWithBackend()
                }
            } else {
                print("⚠️ Trial integrity check failed - potential tampering")
                // Fetch from backend as source of truth
                if let backendTrial = await fetchTrialFromBackend() {
                    self.trialState = backendTrial
                    await saveTrialToKeychain(backendTrial)
                    print("🎫 Trial restored from backend after integrity failure")
                }
            }
        } else {
            print("🎫 No existing trial found - checking backend")
            
            // Check backend in non-blocking way to avoid hanging on network issues
            Task {
                // Check if device has trial in backend (app reinstall scenario)
                let backendTrial = await fetchTrialFromBackend()
                if let trial = backendTrial {
                    await MainActor.run {
                        self.trialState = trial
                    }
                    await saveTrialToKeychain(trial)
                    print("🎫 Restored trial from backend - Day \(trial.daysUsed + 1) of 14")
                } else {
                    // Genuinely new user - trial will be started by AccessSessionManager
                    print("🎫 New user - no existing trial")
                }
            }
        }
    }
    
    /// Start a new trial for first-time users
    func startNewTrial() async throws -> TrialState {
        print("🎫 Starting new 14-day trial...")
        
        // Get persistent device ID
        let deviceId = await getOrCreateDeviceId()
        
        // Create trial state - 14 days
        let now = Date()
        let trialState = TrialState(
            deviceId: deviceId,
            trialStartDate: now,
            trialExpiryDate: Calendar.current.date(byAdding: .day, value: TrialState.trialDurationDays, to: now)!,
            lastPromptShownDate: nil,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        )
        
        // Save to Keychain first (immediate persistence)
        await saveTrialToKeychain(trialState)
        
        // Register with backend
        do {
            try await registerTrialWithBackend(trialState)
        } catch {
            print("⚠️ Failed to register trial with backend: \(error)")
            // Continue anyway - backend sync will retry later
        }
        
        self.trialState = trialState
        return trialState
    }
    
    /// Record trial access (no longer deducts sessions - unlimited during 14 days)
    func recordTrialAccess() async {
        guard let trial = trialState else { return }
        
        guard trial.isValid else { return }
        
        // Just log the access, no deduction needed for unlimited trial
        print("🎫 Trial access recorded - Day \(trial.daysUsed + 1) of \(TrialState.trialDurationDays)")
        
        // Check if we should show payment modal
        if trial.shouldShowPaymentModal && trial.lastPromptShownDate == nil {
            // Will be handled by UI layer
            print("💳 User should see payment modal (day \(trial.daysUsed + 1))")
        }
    }
    
    /// Check if trial is valid
    func isTrialValid() -> Bool {
        return trialState?.isValid ?? false
    }
    
    /// Force sync with backend
    func syncWithBackend() async {
        guard let trial = trialState else { return }
        
        isVerifying = true
        defer { isVerifying = false }
        
        do {
            // Verify trial with backend
            let backendTrial = try await verifyTrialWithBackend(trial)
            
            // Use backend as source of truth
            if let backendTrial = backendTrial {
                self.trialState = backendTrial
                await saveTrialToKeychain(backendTrial)
            }
        } catch {
            print("⚠️ Backend sync failed: \(error)")
            lastSyncError = error
        }
    }
    
    // MARK: - Private Methods
    
    /// Get or create persistent device ID
    private func getOrCreateDeviceId() async -> UUID {
        // First check Keychain for existing ID
        if let deviceIdString = try? await keychainService.getString(
            for: TrialKeys.deviceId,
            service: TrialKeys.service
        ), let deviceId = UUID(uuidString: deviceIdString) {
            return deviceId
        }
        
        // Create new device ID and persist it
        let newDeviceId = UUID()
        try? await keychainService.setString(
            newDeviceId.uuidString,
            for: TrialKeys.deviceId,
            service: TrialKeys.service
        )
        
        return newDeviceId
    }
    
    /// Load trial from Keychain
    private func loadTrialFromKeychain() async -> TrialState? {
        guard let data = try? await keychainService.getData(
            for: TrialKeys.trialData,
            service: TrialKeys.service
        ) else {
            return nil
        }
        
        do {
            let trial = try JSONDecoder().decode(TrialState.self, from: data)
            return trial
        } catch {
            print("❌ Failed to decode trial data: \(error)")
            return nil
        }
    }
    
    /// Save trial to Keychain with verification hash
    private func saveTrialToKeychain(_ trial: TrialState) async {
        do {
            let data = try JSONEncoder().encode(trial)
            
            // Save trial data
            try await keychainService.setData(
                data,
                for: TrialKeys.trialData,
                service: TrialKeys.service
            )
            
            // Generate and save verification hash
            let hash = generateVerificationHash(for: trial)
            try await keychainService.setString(
                hash,
                for: TrialKeys.verificationHash,
                service: TrialKeys.service
            )
            
            print("✅ Trial saved to Keychain")
        } catch {
            print("❌ Failed to save trial to Keychain: \(error)")
        }
    }
    
    /// Generate verification hash for tamper detection
    private func generateVerificationHash(for trial: TrialState) -> String {
        let components = "\(trial.deviceId):\(trial.trialStartDate.timeIntervalSince1970):\(trial.trialExpiryDate.timeIntervalSince1970):\(hashSalt)"
        let data = Data(components.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Verify trial integrity
    private func verifyTrialIntegrity(_ trial: TrialState) async -> Bool {
        guard let storedHash = try? await keychainService.getString(
            for: TrialKeys.verificationHash,
            service: TrialKeys.service
        ) else {
            return false
        }
        
        let calculatedHash = generateVerificationHash(for: trial)
        return storedHash == calculatedHash
    }
    
    // MARK: - Backend Integration
    
    /// Register new trial with backend
    private func registerTrialWithBackend(_ trial: TrialState) async throws {
        // Skip if Supabase not configured
        guard ProcessInfo.processInfo.environment["SUPABASE_URL"] != nil else {
            print("⚠️ Supabase not configured - skipping backend registration")
            return
        }
        
        let endpoint = "/api/trial/start"
        
        let deviceInfo: [String: Any] = [
            "device_id": trial.deviceId.uuidString,
            "device_model": UIDevice.current.model,
            "ios_version": UIDevice.current.systemVersion,
            "app_version": trial.appVersion,
            "trial_started_at": ISO8601DateFormatter().string(from: trial.trialStartDate),
            "trial_expires_at": ISO8601DateFormatter().string(from: trial.trialExpiryDate),
            "trial_type": "unlimited_14_day"
        ]
        
        let _: TrialStartResponse = try await networkManager.request(
            endpoint: endpoint,
            method: .post,
            body: deviceInfo
        )
        
        print("✅ Trial registered with backend")
    }
    
    /// Fetch trial from backend (for app reinstall scenario)
    private func fetchTrialFromBackend() async -> TrialState? {
        // Skip backend check if not configured
        if ProcessInfo.processInfo.environment["SUPABASE_URL"] == nil {
            print("⚠️ Supabase not configured - skipping backend check")
            return nil
        }
        
        let deviceId = await getOrCreateDeviceId()
        let endpoint = "/api/trial/verify"
        
        do {
            let response: TrialVerifyResponse = try await networkManager.request(
                endpoint: endpoint,
                method: .post,
                body: ["device_id": deviceId.uuidString]
            )
            
            guard response.valid, let trialData = response.trial_state else {
                return nil
            }
            
            // Parse backend response
            return parseBackendTrialState(trialData, deviceId: deviceId)
        } catch {
            print("⚠️ Failed to fetch trial from backend: \(error)")
            return nil
        }
    }
    
    /// Verify trial with backend
    private func verifyTrialWithBackend(_ trial: TrialState) async throws -> TrialState? {
        let endpoint = "/api/trial/verify"
        
        let body: [String: Any] = [
            "device_id": trial.deviceId.uuidString,
            "trial_data": [
                "started_at": ISO8601DateFormatter().string(from: trial.trialStartDate)
            ]
        ]
        
        let response: TrialVerifyResponse = try await networkManager.request(
            endpoint: endpoint,
            method: .post,
            body: body
        )
        
        guard response.valid, let trialData = response.trial_state else {
            return nil
        }
        
        return parseBackendTrialState(trialData, deviceId: trial.deviceId)
    }
    
    /// Record trial access in backend (no session counting needed)
    private func recordTrialAccessInBackend(_ trial: TrialState) async throws {
        // Skip if Supabase not configured
        guard ProcessInfo.processInfo.environment["SUPABASE_URL"] != nil else {
            return
        }
        
        let endpoint = "/api/trial/access"
        
        let body: [String: Any] = [
            "device_id": trial.deviceId.uuidString,
            "accessed_at": ISO8601DateFormatter().string(from: Date()),
            "day_of_trial": trial.daysUsed + 1
        ]
        
        let _: TrialSessionResponse = try await networkManager.request(
            endpoint: endpoint,
            method: .post,
            body: body
        )
    }
    
    /// Parse backend trial state response
    private func parseBackendTrialState(_ data: TrialStateResponse, deviceId: UUID) -> TrialState? {
        let formatter = ISO8601DateFormatter()
        
        guard let startedAt = formatter.date(from: data.started_at),
              let expiresAt = formatter.date(from: data.expires_at) else {
            return nil
        }
        
        return TrialState(
            deviceId: deviceId,
            trialStartDate: startedAt,
            trialExpiryDate: expiresAt,
            lastPromptShownDate: nil,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        )
    }
    
    // MARK: - Migration for Existing Users
    
    /// Migrate existing trial data from old format
    func migrateExistingTrial() async {
        // Check UserDefaults for old trial data
        let defaults = UserDefaults.standard
        
        // Check for existing trial start date
        if let oldTrialStart = defaults.object(forKey: "trialStartDate") as? Date {
            print("🔄 Migrating existing trial data...")
            
            let deviceId = await getOrCreateDeviceId()
            
            // Migrate to 14-day trial from old 7-day trial
            let trial = TrialState(
                deviceId: deviceId,
                trialStartDate: oldTrialStart,
                trialExpiryDate: Calendar.current.date(byAdding: .day, value: 14, to: oldTrialStart)!,
                lastPromptShownDate: nil,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
            )
            
            await saveTrialToKeychain(trial)
            self.trialState = trial
            
            // Clean up old data
            defaults.removeObject(forKey: "trialStartDate")
            defaults.removeObject(forKey: "hasUsedTrial")
            
            print("✅ Trial migration completed")
        }
    }
}

// MARK: - Error Types

enum TrialPersistenceError: LocalizedError {
    case noTrialFound
    case trialExpired
    case verificationFailed
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noTrialFound:
            return "No trial found for this device"
        case .trialExpired:
            return "Your trial has expired"
        case .verificationFailed:
            return "Trial verification failed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}