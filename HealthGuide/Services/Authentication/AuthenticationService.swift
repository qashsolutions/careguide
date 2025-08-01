//
//  AuthenticationService.swift
//  HealthGuide
////
//  AuthenticationService.swift
//  HealthGuide
//
//  Core authentication service wrapping LocalAuthentication framework
//  Swift 6 compliant with proper async/await patterns
//

import Foundation
import LocalAuthentication

// MARK: - Authentication Service
/// Service responsible for direct interaction with LocalAuthentication framework
/// Handles biometric and passcode authentication operations
actor AuthenticationService {
    
    // MARK: - Public Methods
    
    /// Perform biometric authentication using Face ID or Touch ID
    /// - Parameter reason: Localized reason shown to user during authentication
    /// - Returns: AuthenticationResult indicating success, failure, or cancellation
    func performBiometricAuthentication(reason: String) async -> AuthenticationResult {
        let context = createAuthenticationContext()
        
        do {
            // Use direct callback-based API for better performance per iOS engineer feedback
            let success = try await evaluatePolicy(
                context: context,
                policy: .deviceOwnerAuthentication,
                reason: reason
            )
            
            return success ? .success : .failed(.biometricAuthenticationFailed(reason: "Authentication failed"))
            
        } catch let error as LAError {
            return mapLAErrorToResult(error)
        } catch {
            return .failed(.biometricAuthenticationFailed(reason: error.localizedDescription))
        }
    }
    
    /// Check biometric availability and determine supported biometric type
    /// - Returns: BiometricAvailabilityResult with available type or error
    func checkBiometricAvailability() async -> BiometricAvailabilityResult {
        let context = createAuthenticationContext()
        var error: NSError?
        
        // Check if device supports biometric authentication
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        
        if canEvaluate {
            let biometricType = mapLABiometryType(context.biometryType)
            return .available(biometricType)
        } else if let laError = error as? LAError {
            let appError = mapLAErrorToAppError(laError)
            return .unavailable(appError)
        } else {
            return .unavailable(.biometricNotAvailable)
        }
    }
    
    /// Perform passcode authentication as fallback option
    /// - Returns: AuthenticationResult indicating success or failure
    func performPasscodeAuthentication() async -> AuthenticationResult {
        // Check if passcode fallback is allowed by configuration
        guard Configuration.BiometricAuth.allowPasscodeFallback else {
            return .failed(.biometricAuthenticationFailed(reason: "Passcode not allowed"))
        }
        
        let context = createAuthenticationContext()
        
        do {
            let success = try await evaluatePolicy(
                context: context,
                policy: .deviceOwnerAuthentication,
                reason: AuthenticationConfiguration.passcodeReason
            )
            
            return success ? .success : .failed(.biometricAuthenticationFailed(reason: "Passcode authentication failed"))
            
        } catch {
            return .failed(.biometricAuthenticationFailed(reason: "Passcode authentication failed"))
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Create a new LAContext instance with proper configuration
    /// - Returns: Configured LAContext ready for authentication
    private func createAuthenticationContext() -> LAContext {
        let context = LAContext()
        
        // Configure context for optimal user experience
        context.localizedFallbackTitle = Configuration.BiometricAuth.allowPasscodeFallback ? "Use Passcode" : ""
        context.localizedCancelTitle = "Cancel"
        
        return context
    }
    
    /// Evaluate authentication policy using callback-to-async bridge
    /// Direct callback usage per iOS engineer feedback to avoid code bloat
    /// - Parameters:
    ///   - context: LAContext instance
    ///   - policy: LAPolicy to evaluate
    ///   - reason: Localized reason for authentication
    /// - Returns: Boolean indicating authentication success
    private func evaluatePolicy(
        context: LAContext,
        policy: LAPolicy,
        reason: String
    ) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Error Mapping Methods
    
    /// Map LAError to AuthenticationResult for authentication operations
    /// - Parameter error: LAError from LocalAuthentication framework
    /// - Returns: Appropriate AuthenticationResult
    private func mapLAErrorToResult(_ error: LAError) -> AuthenticationResult {
        switch error {
        case LAError.biometryNotEnrolled, LAError.passcodeNotSet:
            return .failed(.biometricNotEnrolled)
            
        case LAError.biometryNotAvailable:
            return .failed(.biometricNotAvailable)
            
        case LAError.userCancel, LAError.systemCancel:
            return .cancelled
            
        case LAError.authenticationFailed:
            return .failed(.biometricAuthenticationFailed(reason: "Authentication failed"))
            
        case LAError.userFallback:
            return .failed(.biometricAuthenticationFailed(reason: "Fallback requested"))
            
        case LAError.biometryLockout:
            let lockoutMinutes = Int(Configuration.BiometricAuth.lockoutDuration / 60)
            return .lockedOut(minutes: lockoutMinutes)
            
        case LAError.invalidContext:
            return .failed(.biometricAuthenticationFailed(reason: "Invalid authentication context"))
            
        case LAError.notInteractive:
            return .failed(.biometricAuthenticationFailed(reason: "Authentication not available"))
            
        case LAError.appCancel:
            return .cancelled
            
        default:
            return .failed(.biometricAuthenticationFailed(reason: error.localizedDescription))
        }
    }
    
    /// Map LAError to AppError for availability checks
    /// - Parameter error: LAError from availability check
    /// - Returns: Corresponding AppError
    private func mapLAErrorToAppError(_ error: LAError) -> AppError {
        switch error.code {
        case .biometryNotEnrolled, .passcodeNotSet:
            return .biometricNotEnrolled
        case .biometryNotAvailable:
            return .biometricNotAvailable
        default:
            return .biometricAuthenticationFailed(reason: error.localizedDescription)
        }
    }
    
    /// Map LABiometryType to app-specific BiometricType
    /// - Parameter type: LABiometryType from system
    /// - Returns: App-specific BiometricType enum
    private func mapLABiometryType(_ type: LABiometryType) -> BiometricType {
        switch type {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .none:
            return .none
        case .opticID:
            return .none  // Optic ID not yet supported in this app
        @unknown default:
            return .none
        }
    }
}
