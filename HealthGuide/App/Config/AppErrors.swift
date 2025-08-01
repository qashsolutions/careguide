//
//  AppErrors.swift
//  HealthGuide
//
//  Centralized error definitions with user-friendly messages
//  Elder-friendly language, no technical jargon
//

import Foundation

@available(iOS 18.0, *)
enum AppError: LocalizedError {
    
    // MARK: - Health Data Errors
    case medicationLimitExceeded(current: Int, maximum: Int)
    case supplementLimitExceeded(current: Int, maximum: Int)
    case invalidSchedule(reason: String)
    case duplicateMedication(name: String)
    case invalidDosage(medication: String)
    case scheduleConflict(medication: String, time: String)
    
    // MARK: - Authentication Errors
    case biometricAuthenticationFailed(reason: String)
    case biometricNotAvailable
    case biometricNotEnrolled
    case authenticationRequired
    case tooManyAttempts(lockoutMinutes: Int)
    
    // MARK: - Network Errors
    case networkUnavailable
    case apiRequestFailed(service: String)
    case apiKeyMissing(service: String)
    case requestTimeout
    case invalidResponse
    
    // MARK: - Data Persistence Errors
    case coreDataSaveFailed
    case coreDataFetchFailed
    case dataCorrupted
    case insufficientStorage
    
    // MARK: - Subscription Errors
    case subscriptionExpired
    case paymentFailed(reason: String)
    case subscriptionRestoreFailed
    case invalidProduct
    
    // MARK: - Group Errors
    case invalidInviteCode
    case inviteCodeExpired
    case groupFull(maxMembers: Int)
    case notGroupAdmin
    case alreadyInGroup
    
    // MARK: - Validation Errors
    case nameTooShort(minimum: Int)
    case nameTooLong(maximum: Int)
    case invalidCharacters(field: String)
    case missingRequiredField(field: String)
    
    // MARK: - AI Service Errors
    case conflictCheckFailed(medication: String)
    case suggestionServiceUnavailable
    case voiceProcessingFailed
    
    // MARK: - Internal Errors
    case internalError(_ message: String)
    
    // MARK: - User-Friendly Error Descriptions
    var errorDescription: String? {
        switch self {
        // Health Data Errors
        case .medicationLimitExceeded(let current, let maximum):
            return "Cannot add medication. You have \(current) doses scheduled today. Maximum \(maximum) doses per day allowed for safety."
            
        case .supplementLimitExceeded(let current, let maximum):
            return "Cannot add supplement. You have \(current) doses scheduled today. Maximum \(maximum) doses per day allowed."
            
        case .invalidSchedule(let reason):
            return "Schedule issue: \(reason)"
            
        case .duplicateMedication(let name):
            return "\(name) is already in your medication list. Would you like to edit the existing entry?"
            
        case .invalidDosage(let medication):
            return "Please enter a valid dosage for \(medication)."
            
        case .scheduleConflict(let medication, let time):
            return "\(medication) is already scheduled for \(time)."
            
        // Authentication Errors
        case .biometricAuthenticationFailed(let reason):
            return "Authentication failed: \(reason). Please try again."
            
        case .biometricNotAvailable:
            return "Face ID or Touch ID is not available on this device."
            
        case .biometricNotEnrolled:
            return "Please set up Face ID or Touch ID in Settings first."
            
        case .authenticationRequired:
            return "Please authenticate to access your health data."
            
        case .tooManyAttempts(let lockoutMinutes):
            return "Too many failed attempts. Please try again in \(lockoutMinutes) minutes."
            
        // Network Errors
        case .networkUnavailable:
            return "No internet connection. Some features may be limited."
            
        case .apiRequestFailed(let service):
            return "Could not connect to \(service). Please try again."
            
        case .apiKeyMissing(let service):
            return "\(service) is not configured. Please contact support."
            
        case .requestTimeout:
            return "Request took too long. Please check your connection and try again."
            
        case .invalidResponse:
            return "Received unexpected data. Please try again."
            
        // Data Persistence Errors
        case .coreDataSaveFailed:
            return "Could not save your data. Please try again."
            
        case .coreDataFetchFailed:
            return "Could not load your data. Please restart the app."
            
        case .dataCorrupted:
            return "Data issue detected. Please contact support."
            
        case .insufficientStorage:
            return "Not enough storage space. Please free up some space."
            
        // Subscription Errors
        case .subscriptionExpired:
            return "Your subscription has expired. Please renew to continue."
            
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
            
        case .subscriptionRestoreFailed:
            return "Could not restore your subscription. Please try again."
            
        case .invalidProduct:
            return "Subscription plan not available. Please try again later."
            
        // Group Errors
        case .invalidInviteCode:
            return "Invalid invite code. Please check and try again."
            
        case .inviteCodeExpired:
            return "This invite code has expired. Please request a new one."
            
        case .groupFull(let maxMembers):
            return "This group is full (maximum \(maxMembers) members)."
            
        case .notGroupAdmin:
            return "Only group admins can make changes."
            
        case .alreadyInGroup:
            return "You're already a member of this group."
            
        // Validation Errors
        case .nameTooShort(let minimum):
            return "Name must be at least \(minimum) characters."
            
        case .nameTooLong(let maximum):
            return "Name must be less than \(maximum) characters."
            
        case .invalidCharacters(let field):
            return "\(field) contains invalid characters."
            
        case .missingRequiredField(let field):
            return "Please enter \(field)."
            
        // AI Service Errors
        case .conflictCheckFailed(let medication):
            return "Could not check conflicts for \(medication). Please try again."
            
        case .suggestionServiceUnavailable:
            return "Suggestions temporarily unavailable. You can still type manually."
            
        case .voiceProcessingFailed:
            return "Could not process voice command. Please try again or type manually."
            
        // Internal Errors
        case .internalError(let message):
            return "System error: \(message)"
        }
    }
    
    // MARK: - Recovery Suggestions
    var recoverySuggestion: String? {
        switch self {
        case .medicationLimitExceeded, .supplementLimitExceeded:
            return "Edit existing items or wait until tomorrow to add more."
            
        case .biometricNotEnrolled:
            return "Go to Settings > Face ID & Passcode to set up."
            
        case .networkUnavailable:
            return "Check your Wi-Fi or cellular connection."
            
        case .insufficientStorage:
            return "Delete unused apps or photos to free up space."
            
        case .subscriptionExpired:
            return "Tap here to view subscription options."
            
        case .tooManyAttempts:
            return "Wait a few minutes before trying again."
            
        default:
            return nil
        }
    }
    
    // MARK: - User Action Required
    var requiresUserAction: Bool {
        switch self {
        case .biometricNotEnrolled,
             .subscriptionExpired,
             .insufficientStorage,
             .networkUnavailable:
            return true
        default:
            return false
        }
    }
}