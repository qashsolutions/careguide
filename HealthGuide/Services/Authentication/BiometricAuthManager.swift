//
//  BiometricAuthManager.swift
//  HealthGuide
//
//  Main coordinator for biometric authentication
//  Swift 6 compliant with proper concurrency and state management
//

import Foundation

// MARK: - Biometric Authentication Manager
/// Main coordinator class for biometric authentication functionality
/// Manages state, coordinates services, and handles app lifecycle events
@available(iOS 18.0, *)
@MainActor
final class BiometricAuthManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = BiometricAuthManager()
    
    // MARK: - Published Properties (Main Actor Isolated)
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authError: AppError?
    @Published private(set) var biometricType: BiometricType = .none
    
    // MARK: - Private Properties
    private let lockoutManager: LockoutManager
    private let authenticationService = AuthenticationService()
    private var authenticationTask: Task<Void, Never>?
    
    // MARK: - Initialization
    private init() {
        print("🔐 BiometricAuthManager: Initializing...")
        // Initialize lockout manager with configuration
        self.lockoutManager = LockoutManager()
        
        // Validate required Info.plist entries for App Store submission
        validateInfoPlistConfiguration()
        
        // Initialize biometric availability
        Task {
            await self.checkBiometricAvailability()
        }
    }
    
    // MARK: - Public Properties
    
    /// Check if biometric authentication is available and enabled
    var isBiometricEnabled: Bool {
        biometricType != .none
    }
    
    // MARK: - Public Authentication Methods
    
    /// Primary authentication method using biometrics
    /// - Parameter reason: Optional custom reason for authentication prompt
    /// - Returns: True if authentication succeeded, false otherwise
    func authenticate(reason: String? = nil) async -> Bool {
        print("🔒 BiometricAuthManager: Starting authentication...")
        // Check for task cancellation to support cooperative cancellation
        guard !Task.isCancelled else { return false }
        
        // Check lockout status before attempting authentication
        let lockoutStatus = await lockoutManager.checkLockoutStatus()
        if lockoutStatus.isLocked {
            print("❌ BiometricAuthManager: User is locked out for \(lockoutStatus.remainingMinutes) minutes")
            await updateAuthenticationState(
                isAuthenticating: false,
                error: .tooManyAttempts(lockoutMinutes: lockoutStatus.remainingMinutes)
            )
            return false
        }
        
        // Verify biometric availability
        guard await getCurrentBiometricType() != .none else {
            await updateAuthenticationState(
                isAuthenticating: false,
                error: .biometricNotAvailable
            )
            return false
        }
        
        // Update UI to show authentication in progress
        await updateAuthenticationState(isAuthenticating: true, error: nil)
        
        // Perform authentication
        let authReason = reason ?? AuthenticationConfiguration.defaultReason
        let result = await authenticationService.performBiometricAuthentication(reason: authReason)
        
        // Handle result and update state
        await handleAuthenticationResult(result)
        
        // Clear authenticating state
        await updateAuthenticationState(isAuthenticating: false, error: nil)
        
        // Return authentication status
        return self.isAuthenticated
    }
    
    /// Clear authentication state and log out user
    func logout() {
        Task { @MainActor in
            self.isAuthenticated = false
            self.authError = nil
        }
    }
    
    /// Request user to enroll in biometric authentication
    /// Provides appropriate error message based on availability
    func requestBiometricEnrollment() {
        Task {
            let currentType = await getCurrentBiometricType()
            let error: AppError = currentType == .none ? .biometricNotAvailable : .biometricNotEnrolled
            
            await MainActor.run {
                self.authError = error
            }
        }
    }
    
    // MARK: - Biometric Availability
    
    /// Check and update biometric availability status
    func checkBiometricAvailability() async {
        let availabilityResult = await authenticationService.checkBiometricAvailability()
        
        await MainActor.run {
            switch availabilityResult {
            case .available(let type):
                self.biometricType = type
                self.authError = nil
            case .unavailable(let error):
                self.biometricType = .none
                self.authError = error
            }
        }
    }
    
    // MARK: - App Lifecycle Management
    
    /// Handle app becoming active - authenticate if required
    @MainActor
    func handleAppBecameActive() {
        // Only proceed if authentication is required and user isn't already authenticated
        guard Configuration.BiometricAuth.requireAuthOnLaunch && !isAuthenticated else { return }
        
        // Cancel any existing authentication task to prevent duplicates
        authenticationTask?.cancel()
        
        // Start new authentication task on background queue
        authenticationTask = Task { [weak self] in
            guard let self = self else { return }
            _ = await self.authenticate(reason: " ")
        }
    }
    
    /// Handle app resigning active state - cleanup and logout if required
    @MainActor
    func handleAppWillResignActive() {
        // Cancel ongoing authentication to prevent background processing
        authenticationTask?.cancel()
        authenticationTask = nil
        
        // Logout if required by security configuration
        if Configuration.BiometricAuth.requireAuthOnLaunch {
            logout()
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Handle authentication result and update app state accordingly
    /// - Parameter result: Result from authentication attempt
    private func handleAuthenticationResult(_ result: AuthenticationResult) async {
        switch result {
        case .success:
            print("✅ BiometricAuthManager: Authentication successful")
            await lockoutManager.reset()
            await MainActor.run {
                self.isAuthenticated = true
                self.authError = nil
            }
            
        case .cancelled:
            print("⚠️ BiometricAuthManager: Authentication cancelled by user")
            // User cancelled - no error state needed
            await MainActor.run {
                self.authError = nil
            }
            
        case .failed(let error):
            print("❌ BiometricAuthManager: Authentication failed - \(error)")
            await handleAuthenticationFailure(error: error)
            
        case .lockedOut(let minutes):
            await lockoutManager.setMaxFailures()
            await MainActor.run {
                self.authError = .tooManyAttempts(lockoutMinutes: minutes)
            }
        }
    }
    
    /// Handle authentication failure with retry logic
    /// - Parameter error: The authentication error that occurred
    private func handleAuthenticationFailure(error: AppError) async {
        await lockoutManager.recordFailure()
        let remainingAttempts = await lockoutManager.getRemainingAttempts()
        
        // Check if maximum attempts reached
        if remainingAttempts <= 0 {
            let lockoutMinutes = Int(Configuration.BiometricAuth.lockoutDuration / 60)
            await MainActor.run {
                self.authError = .tooManyAttempts(lockoutMinutes: lockoutMinutes)
            }
        } else {
            // Show remaining attempts to user
            await MainActor.run {
                self.authError = .biometricAuthenticationFailed(
                    reason: "\(remainingAttempts) attempts remaining"
                )
            }
        }
    }
    
    /// Update authentication state on main actor
    /// - Parameters:
    ///   - isAuthenticating: Optional new authenticating state
    ///   - error: Optional error to set
    private func updateAuthenticationState(
        isAuthenticating: Bool? = nil,
        error: AppError? = nil
    ) async {
        await MainActor.run {
            if let isAuthenticating = isAuthenticating {
                self.isAuthenticating = isAuthenticating
            }
            if error != nil {
                self.authError = error
            }
        }
    }
    
    /// Get current biometric type safely from main actor
    /// - Returns: Current biometric type
    private func getCurrentBiometricType() async -> BiometricType {
        await MainActor.run {
            self.biometricType
        }
    }
    
    /// Validate required Info.plist configuration for App Store submission
    private func validateInfoPlistConfiguration() {
        #if !DEBUG
        assert(
            Bundle.main.object(forInfoDictionaryKey: AuthenticationConfiguration.faceIDUsageKey) != nil,
            AuthenticationConfiguration.missingInfoPlistMessage
        )
        #endif
    }
}
