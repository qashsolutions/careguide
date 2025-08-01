//
//  KeychainAPIManager.swift
//  HealthGuide
//
//  Secure storage for API keys using iOS Keychain
//  Handles reading from HealthGuide.plist and storing in Keychain
//

import Foundation
import Security

/// Manager for securely storing and retrieving API keys
/// Uses @unchecked Sendable because Keychain operations are inherently thread-safe
/// and this class has no mutable state after initialization
@available(iOS 18.0, *)
final class KeychainAPIManager: @unchecked Sendable {
    
    // MARK: - Singleton
    static let shared = KeychainAPIManager()
    
    // MARK: - Constants
    private enum KeychainKeys {
        static let service = "com.medicationmanager.HealthGuide"
        static let claudeAIKey = "Claude-AI-API-Key"
        static let geminiKey = "Google-Gemini-API-Key"
    }
    
    private enum PlistKeys {
        static let fileName = "HealthGuide"
        static let claudeAI = "ClaudeAIAPIKey"
        static let gemini = "GeminiAPIKey"
    }
    
    // MARK: - API Configuration
    struct APIConfiguration {
        static let claudeModel = "claude-4-sonnet"  // Claude 4 Sonnet (not 3.5 or 3)
        static let geminiModel = "gemini-2.5-pro"   // Gemini 2.5 Pro
        static let claudeBaseURL = "https://api.anthropic.com/v1"
        static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1beta"
    }
    
    // MARK: - Initialization
    private init() {
        print("🔑 KeychainAPIManager: Initializing...")
        loadAPIKeysFromPlist()
    }
    
    // MARK: - Public Methods
    
    /// Get Claude AI API key from Keychain
    func getClaudeAIKey() -> String? {
        return getKey(for: KeychainKeys.claudeAIKey)
    }
    
    /// Get Google Gemini API key from Keychain
    func getGeminiKey() -> String? {
        return getKey(for: KeychainKeys.geminiKey)
    }
    
    // MARK: - Private Methods
    
    /// Load API keys from plist and store in Keychain
    private func loadAPIKeysFromPlist() {
        guard let plistPath = Bundle.main.path(forResource: PlistKeys.fileName, ofType: "plist"),
              let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            print("⚠️ KeychainAPIManager: HealthGuide.plist not found or invalid")
            return
        }
        
        print("📋 KeychainAPIManager: Loading API keys from plist...")
        
        // Store each API key in Keychain
        if let claudeKey = plist[PlistKeys.claudeAI] as? String {
            saveKey(claudeKey, for: KeychainKeys.claudeAIKey)
            print("✅ KeychainAPIManager: Claude AI key stored")
        }
        
        if let geminiKey = plist[PlistKeys.gemini] as? String {
            saveKey(geminiKey, for: KeychainKeys.geminiKey)
            print("✅ KeychainAPIManager: Google Gemini key stored")
        }
    }
    
    /// Save key to Keychain
    private func saveKey(_ key: String, for account: String) {
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("❌ KeychainAPIManager: Failed to save \(account): \(status)")
        }
    }
    
    /// Retrieve key from Keychain
    private func getKey(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        
        print("⚠️ KeychainAPIManager: No key found for \(account)")
        return nil
    }
    
    /// Delete all API keys from Keychain (for testing/reset)
    func deleteAllKeys() {
        let accounts = [KeychainKeys.claudeAIKey, KeychainKeys.geminiKey]
        
        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KeychainKeys.service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
        
        print("🗑️ KeychainAPIManager: All keys deleted from Keychain")
    }
}

// MARK: - Usage Extension
extension KeychainAPIManager {
    /// Check if all required API keys are available
    var hasAllRequiredKeys: Bool {
        return getClaudeAIKey() != nil && getGeminiKey() != nil
    }
    
    /// Get missing API keys
    var missingKeys: [String] {
        var missing: [String] = []
        if getClaudeAIKey() == nil { missing.append("Claude AI") }
        if getGeminiKey() == nil { missing.append("Google Gemini") }
        return missing
    }
    
    /// Get API headers for Claude AI
    func getClaudeHeaders() -> [String: String]? {
        guard let apiKey = getClaudeAIKey() else { return nil }
        return [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        ]
    }
    
    /// Get API headers for Gemini
    func getGeminiHeaders() -> [String: String]? {
        guard let apiKey = getGeminiKey() else { return nil }
        return [
            "x-goog-api-key": apiKey,
            "content-type": "application/json"
        ]
    }
}
