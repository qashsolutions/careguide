//
//  LockoutManager.swift
//  HealthGuide
//
//  LockoutManager.swift
//  HealthGuide
//
//  Thread-safe lockout state management for biometric authentication
//  Swift 6 compliant actor implementation
//

import Foundation

// MARK: - Lockout Manager Actor
/// Thread-safe actor for managing authentication failure state and lockout periods
actor LockoutManager {
    
    // MARK: - Private Properties
    private var failedAttempts = 0
    private var lastAttemptTime: Date?
    
    // MARK: - Configuration
    private let maxRetryAttempts: Int
    private let lockoutDuration: TimeInterval
    
    // MARK: - Initialization
    /// Initialize with configuration values
    /// - Parameters:
    ///   - maxRetryAttempts: Maximum allowed failed attempts before lockout
    ///   - lockoutDuration: Duration of lockout period in seconds
    init(
        maxRetryAttempts: Int = Configuration.BiometricAuth.maxRetryAttempts,
        lockoutDuration: TimeInterval = Configuration.BiometricAuth.lockoutDuration
    ) {
        self.maxRetryAttempts = maxRetryAttempts
        self.lockoutDuration = lockoutDuration
    }
    
    // MARK: - Public Methods
    
    /// Record a failed authentication attempt
    /// Updates failure count and timestamp for lockout calculations
    func recordFailure() {
        failedAttempts += 1
        lastAttemptTime = Date()
    }
    
    /// Reset failure count after successful authentication
    /// Clears all failure tracking data
    func reset() {
        failedAttempts = 0
        lastAttemptTime = nil
    }
    
    /// Set failure count to maximum (for system-level biometric lockout)
    /// Used when LAContext reports biometric lockout
    func setMaxFailures() {
        failedAttempts = maxRetryAttempts
        lastAttemptTime = Date()
    }
    
    /// Get current failure information
    /// - Returns: Tuple containing attempt count and last attempt timestamp
    func getFailureInfo() -> (attempts: Int, lastTime: Date?) {
        return (failedAttempts, lastAttemptTime)
    }
    
    /// Check current lockout status and calculate remaining time
    /// - Returns: LockoutStatus with current state and remaining lockout time
    func checkLockoutStatus() -> LockoutStatus {
        // Not locked if under attempt threshold
        guard failedAttempts >= maxRetryAttempts,
              let lastAttempt = lastAttemptTime else {
            return LockoutStatus(
                isLocked: false,
                remainingMinutes: 0,
                failedAttempts: failedAttempts
            )
        }
        
        // Calculate elapsed time since last attempt
        let elapsed = Date().timeIntervalSince(lastAttempt)
        let remaining = lockoutDuration - elapsed
        
        if remaining > 0 {
            // Still locked out
            return LockoutStatus(
                isLocked: true,
                remainingMinutes: Int(ceil(remaining / 60.0)),
                failedAttempts: failedAttempts
            )
        } else {
            // Lockout period expired, auto-reset
            self.reset()
            return LockoutStatus(
                isLocked: false,
                remainingMinutes: 0,
                failedAttempts: 0
            )
        }
    }
    
    /// Get remaining attempts before lockout
    /// - Returns: Number of attempts remaining, or 0 if already at max
    func getRemainingAttempts() -> Int {
        return max(0, maxRetryAttempts - failedAttempts)
    }
    
    /// Check if currently at maximum failures
    /// - Returns: True if at or above maximum retry attempts
    func isAtMaxFailures() -> Bool {
        return failedAttempts >= maxRetryAttempts
    }
    
    /// Manually expire the lockout (for testing or admin override)
    /// Forces reset regardless of time elapsed
    func expireLockout() {
        reset()
    }
    
    // MARK: - Computed Properties
    
    /// Current failure count
    var currentFailures: Int {
        return failedAttempts
    }
    
    /// Whether any failures have been recorded
    var hasFailures: Bool {
        return failedAttempts > 0
    }
}
