//
//  InviteCodeGenerator.swift
//  HealthGuide
//
//  Cryptographically secure invite code generation for health app
//  HIPAA-compliant random number generation
//

import Foundation
import CryptoKit

@available(iOS 18.0, *)
final class InviteCodeGenerator {
    
    // MARK: - Constants
    private enum Constants {
        static let codeLength = 6
        static let maxAttempts = 10
    }
    
    // MARK: - Initialization
    private init() {
        // Private init to prevent instantiation
    }
    
    // MARK: - Secure Code Generation
    
    /// Generate cryptographically secure 6-digit invite code
    /// - Returns: 6-digit numeric string
    static func generateSecureCode() -> String {
        // Use CryptoKit for secure random generation
        var code = ""
        
        for _ in 0..<Constants.codeLength {
            // Generate secure random digit (0-9)
            let randomByte = SecureRandom.generateRandomByte()
            let digit = Int(randomByte) % 10
            code.append(String(digit))
        }
        
        // Ensure code doesn't start with 0 for better UX
        if code.first == "0" {
            code = regenerateFirstDigit(code)
        }
        
        return code
    }
    
    /// Generate alphanumeric code for enhanced security
    /// - Parameter length: Code length (default 8)
    /// - Returns: Alphanumeric string
    static func generateAlphanumericCode(length: Int = 8) -> String {
        let charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Exclude confusing characters
        var code = ""
        
        for _ in 0..<length {
            let randomByte = SecureRandom.generateRandomByte()
            let index = Int(randomByte) % charset.count
            let charIndex = charset.index(charset.startIndex, offsetBy: index)
            code.append(charset[charIndex])
        }
        
        return code
    }
    
    /// Validate invite code format
    /// - Parameter code: Code to validate
    /// - Returns: True if valid format
    static func isValidCode(_ code: String) -> Bool {
        // Check length
        guard code.count == Constants.codeLength else { return false }
        
        // Check all digits
        return code.allSatisfy { $0.isNumber }
    }
    
    // MARK: - Private Helpers
    
    private static func regenerateFirstDigit(_ code: String) -> String {
        var mutableCode = code
        let randomByte = SecureRandom.generateRandomByte()
        let digit = (Int(randomByte) % 9) + 1 // 1-9
        mutableCode.replaceSubrange(mutableCode.startIndex...mutableCode.startIndex, 
                                   with: String(digit))
        return mutableCode
    }
}

// MARK: - Secure Random Generation
@available(iOS 18.0, *)
private enum SecureRandom {
    
    /// Generate single secure random byte
    static func generateRandomByte() -> UInt8 {
        var byte: UInt8 = 0
        let result = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
        
        guard result == errSecSuccess else {
            // Fallback to less secure but still random
            print("⚠️ SecureRandom: Falling back to arc4random")
            return UInt8(arc4random_uniform(256))
        }
        
        return byte
    }
    
    /// Generate secure random data
    /// - Parameter count: Number of bytes
    /// - Returns: Random data
    static func generateRandomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        
        guard result == errSecSuccess else {
            // Fallback
            print("⚠️ SecureRandom: Falling back to random data generation")
            return Data((0..<count).map { _ in UInt8.random(in: 0...255) })
        }
        
        return Data(bytes)
    }
}

// MARK: - Testing Support
#if DEBUG
extension InviteCodeGenerator {
    
    /// Generate predictable code for testing
    /// - Warning: Never use in production
    static func generateTestCode() -> String {
        return "123456"
    }
}
#endif