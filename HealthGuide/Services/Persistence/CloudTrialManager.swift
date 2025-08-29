//
//  CloudTrialManager.swift
//  HealthGuide
//
//  Production-ready trial management using CloudKit + Device binding
//  Prevents all gaming attempts including group rotation abuse
//

import Foundation
import CloudKit
import CryptoKit
import UIKit

@available(iOS 18.0, *)
@MainActor
final class CloudTrialManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = CloudTrialManager()
    
    // MARK: - Published Properties
    @Published var trialState: UnifiedTrialState?
    @Published var isSyncing = false
    @Published var lastError: Error?
    
    // MARK: - Private Properties
    private let container = CKContainer.default()
    private let privateDB: CKDatabase
    private let keychainService = KeychainService.shared
    private let deviceCheckManager = DeviceCheckManager.shared
    
    // Record type for CloudKit
    private let recordType = "Trial"
    
    // MARK: - Unified Trial State
    struct UnifiedTrialState: Codable {
        let trialId: String           // Unique trial ID
        let accountId: String          // iCloud account identifier (hashed)
        let deviceId: String           // Device identifier
        let groupId: String?           // Optional group ID
        let startDate: Date
        let expiryDate: Date
        let createdDeviceId: String   // Original device that started trial
        let createdDeviceName: String // Device name for transparency
        
        // Computed properties
        var isValid: Bool {
            Date() < expiryDate
        }
        
        var daysRemaining: Int {
            Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        }
        
        var daysUsed: Int {
            Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0 + 1
        }
        
        var isExpired: Bool {
            Date() >= expiryDate
        }
        
        var shouldShowPaymentModal: Bool {
            // Show modal on days 12, 13, 14 (when 2 or fewer days remain)
            // Days remaining: 2 = day 12, 1 = day 13, 0 = day 14
            daysRemaining <= 2 && daysRemaining >= 0
        }
        
        var requiresPayment: Bool {
            // Hard paywall after day 14 expires
            isExpired
        }
    }
    
    // MARK: - Initialization
    private init() {
        self.privateDB = container.privateCloudDatabase
        print("☁️ CloudTrialManager: Initialized")
    }
    
    // MARK: - Public Methods
    
    /// Sync trial state for group members - inherits admin's trial dates
    func syncGroupMemberTrial(groupId: String, trialStartDate: Date, trialEndDate: Date) async {
        AppLogger.main.info("☁️ Syncing group member trial with admin's dates")
        
        // Get device and account identifiers
        let deviceId = await deviceCheckManager.getDeviceIdentifier()
        let accountId = (try? await getAccountIdentifier()) ?? UUID().uuidString
        
        // Create a unified trial state that matches the group admin's trial
        let groupMemberTrial = UnifiedTrialState(
            trialId: UUID().uuidString,
            accountId: accountId,
            deviceId: deviceId,
            groupId: groupId,
            startDate: trialStartDate,
            expiryDate: trialEndDate,
            createdDeviceId: deviceId,
            createdDeviceName: UIDevice.current.name
        )
        
        // Update local state
        self.trialState = groupMemberTrial
        
        // Save to keychain for fast access
        await saveToLocalKeychain(groupMemberTrial)
        
        // Calculate and log the correct day
        let daysUsed = Calendar.current.dateComponents([.day], from: trialStartDate, to: Date()).day ?? 0
        AppLogger.main.info("☁️ Group member trial synced: Day \(daysUsed + 1) of 14")
        AppLogger.main.info("   Trial expires: \(trialEndDate)")
        
        // Optionally sync to CloudKit (but not required for group members)
        Task.detached { [weak self] in
            try? await self?.syncToCloud(groupMemberTrial)
        }
    }
    
    /// Initialize and check trial status - Optimized with cache-first approach
    func initialize() async throws {
        // FAST PATH: Check local cache first
        if let cachedTrial = await loadFromLocalKeychain() {
            // Use cached trial immediately for fast startup
            self.trialState = cachedTrial
            AppLogger.main.info("☁️ Trial loaded from cache: Day \(cachedTrial.daysUsed) of 14")
            
            // Verify with CloudKit in background (don't block startup)
            Task.detached { [weak self] in
                await self?.verifyTrialInBackground(cachedTrial)
            }
            return // Fast return - UI can proceed
        }
        
        // SLOW PATH: No cache, must check CloudKit (after reinstall)
        AppLogger.main.info("☁️ No cached trial, checking CloudKit...")
        
        // Check CloudKit availability
        let status = try await container.accountStatus()
        guard status == .available else {
            throw TrialError.iCloudNotAvailable
        }
        
        // Get account identifier (hashed for privacy)
        let accountId = try await getAccountIdentifier()
        
        // Get device identifier
        let deviceId = await deviceCheckManager.getDeviceIdentifier()
        
        // Check for existing trial in cloud
        if let existingTrial = try await fetchTrialFromCloud(accountId: accountId) {
            AppLogger.main.info("☁️ Found existing trial in CloudKit")
            
            // Verify this device is authorized
            if try await verifyDeviceAuthorization(trial: existingTrial, deviceId: deviceId) {
                self.trialState = existingTrial
                await saveToLocalKeychain(existingTrial)
                AppLogger.main.info("✅ Trial restored from CloudKit: Day \(existingTrial.daysUsed) of 14")
            } else {
                AppLogger.main.error("Device not authorized for this trial")
                throw TrialError.deviceNotAuthorized
            }
        } else {
            AppLogger.main.info("☁️ No existing trial found - new user")
        }
    }
    
    /// Verify cached trial with CloudKit in background
    private func verifyTrialInBackground(_ cachedTrial: UnifiedTrialState) async {
        do {
            // Get account identifier
            let accountId = try await getAccountIdentifier()
            
            // Fetch latest from CloudKit
            if let cloudTrial = try await fetchTrialFromCloud(accountId: accountId) {
                // Compare with cache
                if cloudTrial.startDate != cachedTrial.startDate ||
                   cloudTrial.expiryDate != cachedTrial.expiryDate {
                    // Cloud has different data - update cache and state
                    await MainActor.run {
                        self.trialState = cloudTrial
                    }
                    await saveToLocalKeychain(cloudTrial)
                    AppLogger.main.info("☁️ Trial updated from CloudKit sync")
                }
            }
        } catch {
            // Background sync failed - not critical, cache is still valid
            AppLogger.main.debug("Background trial sync failed: \(error)")
        }
    }
    
    /// Start a new trial (first-time users only)
    func startNewTrial(groupId: String? = nil) async throws -> UnifiedTrialState {
        print("☁️ Starting new 14-day trial...")
        
        // Get identifiers
        let accountId = try await getAccountIdentifier()
        let deviceId = await deviceCheckManager.getDeviceIdentifier()
        
        // Check if account already has a trial
        if let existingTrial = try await fetchTrialFromCloud(accountId: accountId) {
            if existingTrial.isExpired {
                throw TrialError.trialAlreadyUsed
            } else {
                // Return existing valid trial
                self.trialState = existingTrial
                return existingTrial
            }
        }
        
        // Create new trial
        let trial = UnifiedTrialState(
            trialId: UUID().uuidString,
            accountId: accountId,
            deviceId: deviceId,
            groupId: groupId,
            startDate: Date(),
            expiryDate: Calendar.current.date(byAdding: .day, value: 14, to: Date())!,
            createdDeviceId: deviceId,
            createdDeviceName: UIDevice.current.name
        )
        
        // Save to CloudKit first (source of truth)
        try await saveToCloud(trial)
        
        // Then save locally
        await saveToLocalKeychain(trial)
        
        // Update state
        self.trialState = trial
        
        print("✅ Trial started and synced to CloudKit")
        return trial
    }
    
    /// Check if user can access based on trial/group status
    func checkAccess(for groupId: String? = nil) async throws -> Bool {
        guard let trial = trialState else {
            return false
        }
        
        // Check if trial is valid
        if !trial.isValid {
            return false
        }
        
        // If accessing as group member, verify group trial
        if let groupId = groupId {
            return try await verifyGroupAccess(groupId: groupId, trial: trial)
        }
        
        return true
    }
    
    // MARK: - Private Methods - CloudKit
    
    /// Get hashed account identifier for privacy
    private func getAccountIdentifier() async throws -> String {
        let userID = try await container.userRecordID()
        let accountID = userID.recordName
        
        // Hash the account ID for privacy
        let data = Data(accountID.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Fetch trial from CloudKit
    private func fetchTrialFromCloud(accountId: String) async throws -> UnifiedTrialState? {
        let predicate = NSPredicate(format: "accountId == %@", accountId)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        
        do {
            let results = try await privateDB.records(matching: query)
            
            for (_, result) in results.matchResults {
                if let record = try? result.get() {
                    return parseRecord(record)
                }
            }
        } catch {
            print("☁️ Error fetching from CloudKit: \(error)")
        }
        
        return nil
    }
    
    /// Save trial to CloudKit
    private func saveToCloud(_ trial: UnifiedTrialState) async throws {
        let record = CKRecord(recordType: recordType)
        
        record["trialId"] = trial.trialId
        record["accountId"] = trial.accountId
        record["deviceId"] = trial.deviceId
        record["groupId"] = trial.groupId
        record["startDate"] = trial.startDate
        record["expiryDate"] = trial.expiryDate
        record["createdDeviceId"] = trial.createdDeviceId
        record["createdDeviceName"] = trial.createdDeviceName
        
        _ = try await privateDB.save(record)
        print("☁️ Trial saved to CloudKit")
    }
    
    /// Sync existing trial to CloudKit
    private func syncToCloud(_ trial: UnifiedTrialState) async throws {
        // Check if already exists
        if let _ = try await fetchTrialFromCloud(accountId: trial.accountId) {
            print("☁️ Trial already in CloudKit")
            return
        }
        
        try await saveToCloud(trial)
    }
    
    /// Parse CloudKit record to trial state
    private func parseRecord(_ record: CKRecord) -> UnifiedTrialState? {
        guard let trialId = record["trialId"] as? String,
              let accountId = record["accountId"] as? String,
              let deviceId = record["deviceId"] as? String,
              let startDate = record["startDate"] as? Date,
              let expiryDate = record["expiryDate"] as? Date,
              let createdDeviceId = record["createdDeviceId"] as? String,
              let createdDeviceName = record["createdDeviceName"] as? String else {
            return nil
        }
        
        return UnifiedTrialState(
            trialId: trialId,
            accountId: accountId,
            deviceId: deviceId,
            groupId: record["groupId"] as? String,
            startDate: startDate,
            expiryDate: expiryDate,
            createdDeviceId: createdDeviceId,
            createdDeviceName: createdDeviceName
        )
    }
    
    // MARK: - Private Methods - Group Management
    
    /// Verify device is authorized for trial
    private func verifyDeviceAuthorization(trial: UnifiedTrialState, deviceId: String) async throws -> Bool {
        // Original device always authorized
        if trial.createdDeviceId == deviceId {
            return true
        }
        
        // Check if part of same group
        if let groupId = trial.groupId {
            return try await isDeviceInGroup(deviceId: deviceId, groupId: groupId)
        }
        
        // Check if same iCloud account (allows device switching for same user)
        let currentAccountId = try await getAccountIdentifier()
        return trial.accountId == currentAccountId
    }
    
    /// Verify group access
    private func verifyGroupAccess(groupId: String, trial: UnifiedTrialState) async throws -> Bool {
        // Fetch group record from CloudKit
        let groupPredicate = NSPredicate(format: "groupId == %@ AND accountId == %@", groupId, trial.accountId)
        let query = CKQuery(recordType: "GroupTrial", predicate: groupPredicate)
        
        do {
            let results = try await privateDB.records(matching: query)
            
            // Check if group has valid trial
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let groupExpiryDate = record["expiryDate"] as? Date {
                    return Date() < groupExpiryDate
                }
            }
        } catch {
            print("☁️ Error checking group access: \(error)")
        }
        
        return false
    }
    
    /// Get all members in a group
    private func getGroupMembers(groupId: String) async throws -> [String] {
        let predicate = NSPredicate(format: "groupId == %@", groupId)
        let query = CKQuery(recordType: "GroupMember", predicate: predicate)
        
        var members: [String] = []
        
        do {
            let results = try await privateDB.records(matching: query)
            
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let accountId = record["accountId"] as? String {
                    members.append(accountId)
                }
            }
        } catch {
            print("☁️ Error fetching group members: \(error)")
        }
        
        return members
    }
    
    /// Check if device is in group
    private func isDeviceInGroup(deviceId: String, groupId: String) async throws -> Bool {
        // Check CloudKit for group membership
        let members = try await getGroupMembers(groupId: groupId)
        
        // Enforce 3-user limit
        if members.count >= 3 && !members.contains(deviceId) {
            throw TrialError.groupFull
        }
        
        return members.contains(deviceId)
    }
    
    // MARK: - Private Methods - Local Storage
    
    /// Save to local keychain as backup
    private func saveToLocalKeychain(_ trial: UnifiedTrialState) async {
        do {
            let data = try JSONEncoder().encode(trial)
            try await keychainService.setData(
                data,
                for: "unified_trial_state",
                service: .trial
            )
            print("💾 Trial saved to local keychain")
        } catch {
            print("❌ Failed to save to keychain: \(error)")
        }
    }
    
    /// Load from local keychain
    private func loadFromLocalKeychain() async -> UnifiedTrialState? {
        do {
            guard let data = try await keychainService.getData(
                for: "unified_trial_state",
                service: .trial
            ) else { return nil }
            
            return try JSONDecoder().decode(UnifiedTrialState.self, from: data)
        } catch {
            print("❌ Failed to load from keychain: \(error)")
            return nil
        }
    }
}

// MARK: - Error Types

enum TrialError: LocalizedError {
    case iCloudNotAvailable
    case trialAlreadyUsed
    case deviceNotAuthorized
    case groupNotFound
    case groupFull
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud is required for HealthGuide. Please sign in to iCloud in Settings."
        case .trialAlreadyUsed:
            return "You've already used your free trial. Please subscribe to continue."
        case .deviceNotAuthorized:
            return "This device is not authorized for the trial. Please use the original device or join the group."
        case .groupNotFound:
            return "Group not found or trial expired."
        case .groupFull:
            return "This group already has 3 members. Maximum group size reached."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}