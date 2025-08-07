//
//  KeychainService.swift
//  HealthGuide
//
//  Unified Keychain service for all secure storage needs
//  Production-ready with proper error handling and thread safety
//

import Foundation
import Security

@available(iOS 18.0, *)
actor KeychainService {
    
    // MARK: - Singleton
    static let shared = KeychainService()
    
    // MARK: - Service Identifiers
    enum Service: String {
        case api = "com.healthguide.api"           // API keys
        case device = "com.healthguide.device"     // Device tracking (survives deletion)
        case subscription = "com.healthguide.subscription" // Subscription data
        case user = "com.healthguide.user"         // User credentials
        
        var accessLevel: String {
            switch self {
            case .device:
                // Device tracking needs to survive app deletion
                // Use AfterFirstUnlock for maximum persistence
                return kSecAttrAccessibleAfterFirstUnlock as String
            case .api, .subscription, .user:
                // More secure for sensitive data
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
            }
        }
    }
    
    // MARK: - Error Types
    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case invalidData
        case unhandledError(status: OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in keychain"
            case .duplicateItem:
                return "Duplicate item exists in keychain"
            case .invalidData:
                return "Invalid data format"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    // MARK: - Private Init
    private init() {
        print("🔐 KeychainService: Initialized")
    }
    
    // MARK: - String Operations
    
    /// Store a string value in the keychain
    func setString(_ value: String, for key: String, service: Service) async throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try await setData(data, for: key, service: service)
    }
    
    /// Retrieve a string value from the keychain
    func getString(for key: String, service: Service) async throws -> String? {
        guard let data = try await getData(for: key, service: service) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }
    
    // MARK: - Data Operations
    
    /// Store data in the keychain
    func setData(_ data: Data, for key: String, service: Service) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: service.accessLevel
        ]
        
        // Try to update existing item first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrAccount as String: key
        ]
        
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: service.accessLevel
        ]
        
        var status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        
        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            status = SecItemAdd(query as CFDictionary, nil)
        }
        
        guard status == errSecSuccess else {
            print("❌ KeychainService: Failed to save data for key: \(key), service: \(service.rawValue), status: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        print("✅ KeychainService: Saved data for key: \(key), service: \(service.rawValue)")
    }
    
    /// Retrieve data from the keychain
    func getData(for key: String, service: Service) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            print("❌ KeychainService: Failed to retrieve data for key: \(key), service: \(service.rawValue), status: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    // MARK: - Delete Operations
    
    /// Delete an item from the keychain
    func deleteItem(for key: String, service: Service) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("❌ KeychainService: Failed to delete item for key: \(key), service: \(service.rawValue), status: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        print("✅ KeychainService: Deleted item for key: \(key), service: \(service.rawValue)")
    }
    
    /// Clear all items for a specific service
    func clearService(_ service: Service) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("❌ KeychainService: Failed to clear service: \(service.rawValue), status: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        
        print("✅ KeychainService: Cleared all items for service: \(service.rawValue)")
    }
    
    // MARK: - Utility Methods
    
    /// Check if an item exists in the keychain
    func itemExists(for key: String, service: Service) async -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Migration Helpers
    
    /// Migrate data from old service to new service
    func migrateData(from oldService: String, to newService: Service) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: oldService,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            print("ℹ️ KeychainService: No items to migrate from \(oldService)")
            return
        }
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            throw KeychainError.unhandledError(status: status)
        }
        
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               let data = item[kSecValueData as String] as? Data {
                try await setData(data, for: account, service: newService)
            }
        }
        
        // Delete old items after successful migration
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: oldService
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        print("✅ KeychainService: Migrated \(items.count) items from \(oldService) to \(newService.rawValue)")
    }
}

// MARK: - Convenience Extensions

@available(iOS 18.0, *)
extension KeychainService {
    
    // MARK: - Device Tracking
    
    /// Get or create device identifier
    func getDeviceIdentifier() async -> String {
        if let deviceId = try? await getString(for: "device_identifier", service: .device) {
            return deviceId
        }
        
        let newId = UUID().uuidString
        try? await setString(newId, for: "device_identifier", service: .device)
        return newId
    }
    
    /// Store last access date
    func setLastAccessDate(_ date: Date) async {
        let dateString = ISO8601DateFormatter().string(from: date)
        try? await setString(dateString, for: "last_access_date", service: .device)
    }
    
    /// Get last access date
    func getLastAccessDate() async -> Date? {
        guard let dateString = try? await getString(for: "last_access_date", service: .device) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }
    
    // MARK: - Subscription Tracking
    
    /// Store original transaction ID
    func setOriginalTransactionId(_ transactionId: String) async {
        try? await setString(transactionId, for: "original_transaction_id", service: .subscription)
    }
    
    /// Get original transaction ID
    func getOriginalTransactionId() async -> String? {
        return try? await getString(for: "original_transaction_id", service: .subscription)
    }
}