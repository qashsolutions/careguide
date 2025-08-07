//
//  BiometricTypes.swift
//  HealthGuide
//
//  BiometricTypes.swift
//  HealthGuide
//
//  Shared types and enums for biometric authentication
//  Swift 6 compliant with Sendable conformance
//

import Foundation

// MARK: - Biometric Type Definition
/// Represents the available biometric authentication types
enum BiometricType: Sendable, CaseIterable {
    case none
    case faceID
    case touchID
    
    /// User-friendly display name for the biometric type
    var displayName: String {
        switch self {
        case .none: return "Biometric Authentication"
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        }
    }
    
    /// System icon name for the biometric type
    var iconName: String {
        switch self {
        case .none: return "lock.shield"
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        }
    }
    
    /// Whether this biometric type is available for authentication
    var isAvailable: Bool {
        return self != .none
    }
}

// MARK: - Authentication Result
/// Comprehensive result type for authentication operations
enum AuthenticationResult: Sendable {
    case success
    case cancelled
    case failed(AppError)
    case lockedOut(minutes: Int)
    
    /// Whether the authentication was successful
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
    
    /// Whether the user cancelled the authentication
    var isCancelled: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
    
    /// Whether the authentication failed with an error
    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
    
    /// Whether the user is locked out
    var isLockedOut: Bool {
        if case .lockedOut = self {
            return true
        }
        return false
    }
}

// MARK: - Biometric Availability Result
/// Result of checking biometric availability on the device
enum BiometricAvailabilityResult: Sendable {
    case available(BiometricType)
    case unavailable(AppError)
    
    /// Whether biometrics are available for use
    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
    
    /// The available biometric type (if any)
    var biometricType: BiometricType {
        switch self {
        case .available(let type):
            return type
        case .unavailable:
            return .none
        }
    }
    
    /// The error preventing biometric availability (if any)
    var error: AppError? {
        switch self {
        case .available:
            return nil
        case .unavailable(let error):
            return error
        }
    }
}

// MARK: - Lockout Status
/// Information about the current lockout state
struct LockoutStatus: Sendable, Equatable {
    let isLocked: Bool
    let remainingMinutes: Int
    let failedAttempts: Int
    
    /// Whether the lockout has expired
    var isExpired: Bool {
        return !isLocked && failedAttempts > 0
    }
    
    /// Create a non-locked status
    static let unlocked = LockoutStatus(isLocked: false, remainingMinutes: 0, failedAttempts: 0)
}

// MARK: - Authentication Configuration
/// Configuration constants for authentication behavior
enum AuthenticationConfiguration {
    /// Default authentication reason shown to users
    static let defaultReason = " "
    
    /// Passcode fallback reason
    static let passcodeReason = "Enter your passcode to access health data"
    
    /// Required Info.plist key for Face ID
    static let faceIDUsageKey = "NSFaceIDUsageDescription"
    
    /// Validation message for missing Info.plist entries
    static let missingInfoPlistMessage = "Missing NSFaceIDUsageDescription in Info.plist - required for App Store submission"
}
