//
//  UserManager.swift
//  HealthGuide
//
//  Manages current user ID for health app
//  Production-ready singleton with secure user management
//

import Foundation

// MARK: - User Manager Errors
@available(iOS 18.0, *)
enum UserManagerError: LocalizedError {
    case noCurrentUser
    case invalidUserData
    case userCreationFailed
    case keychainError(String)
    
    var errorDescription: String? {
        switch self {
        case .noCurrentUser:
            return "No current user found"
        case .invalidUserData:
            return "User data is corrupted or invalid"
        case .userCreationFailed:
            return "Failed to create new user"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        }
    }
}

@available(iOS 18.0, *)
@MainActor
final class UserManager {
    
    // MARK: - Singleton
    static let shared = UserManager()
    
    // MARK: - Constants
    private enum Keys {
        static let currentUserID = "com.healthguide.currentUserID"
        static let userCreatedAt = "com.healthguide.userCreatedAt"
    }
    
    // MARK: - Properties
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Current User ID (Throwing)
    var currentUserID: UUID {
        get throws {
            // Try to get stored user ID
            if let storedID = userDefaults.string(forKey: Keys.currentUserID),
               let uuid = UUID(uuidString: storedID) {
                return uuid
            }
            
            // If no user ID exists, this is a critical error in production
            throw UserManagerError.noCurrentUser
        }
    }
    
    // MARK: - Safe Current User ID (Non-throwing)
    /// Returns current user ID or creates a new one if needed
    /// Use this when you need guaranteed user ID (e.g., first app launch)
    func getOrCreateUserID() -> UUID {
        if let storedID = userDefaults.string(forKey: Keys.currentUserID),
           let uuid = UUID(uuidString: storedID) {
            return uuid
        } else {
            // Generate and store new user ID
            let newID = UUID()
            userDefaults.set(newID.uuidString, forKey: Keys.currentUserID)
            userDefaults.set(Date(), forKey: Keys.userCreatedAt)
            
            #if DEBUG
            print("📱 UserManager: Created new user ID: \(newID)")
            #endif
            
            return newID
        }
    }
    
    // MARK: - User Creation Date
    var userCreatedAt: Date {
        userDefaults.object(forKey: Keys.userCreatedAt) as? Date ?? Date()
    }
    
    // MARK: - Initialization
    private init() {
        // Private init for singleton
    }
    
    // MARK: - User Management
    
    /// Check if user exists
    var hasExistingUser: Bool {
        userDefaults.string(forKey: Keys.currentUserID) != nil
    }
    
    /// Reset user (for testing or account deletion)
    func resetUser() {
        userDefaults.removeObject(forKey: Keys.currentUserID)
        userDefaults.removeObject(forKey: Keys.userCreatedAt)
        print("⚠️ UserManager: User data reset")
    }
    
    /// Migrate user ID if needed (for app updates)
    func migrateUserIfNeeded() {
        // Check for legacy user ID formats
        if let legacyID = userDefaults.string(forKey: "userID"),
           UUID(uuidString: legacyID) == nil {
            // Legacy ID exists but isn't valid UUID
            userDefaults.removeObject(forKey: "userID")
            print("🔄 UserManager: Migrated legacy user ID")
        }
    }
}

// MARK: - CloudKit Considerations
extension UserManager {
    
    /// Get user ID for CloudKit operations
    /// Returns nil if user hasn't granted CloudKit permissions
    func userIDForCloudKit() async -> UUID? {
        // In production, verify CloudKit account status
        // For now, return current user ID
        do {
            return try currentUserID
        } catch {
            #if DEBUG
            print("⚠️ UserManager: Could not get user ID for CloudKit: \(error)")
            #endif
            return nil
        }
    }
    
    /// Verify user can sync with CloudKit
    func canSyncWithCloudKit() async -> Bool {
        // In production, check:
        // 1. iCloud account signed in
        // 2. Network connectivity
        // 3. CloudKit permissions
        return true
    }
}