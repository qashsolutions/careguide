//
//  Configuration.swift
//  HealthGuide
//
//  Environment configuration and constants
//  NO HARDCODED VALUES - Everything configurable here
//

import Foundation

@available(iOS 18.0, *)
enum Configuration: Sendable {
    
    // MARK: - App Environment
    enum Environment {
        static let isProduction = Bundle.main.object(forInfoDictionaryKey: "IS_PRODUCTION") as? Bool ?? true
        static let isDevelopment = !isProduction
    }
    
    // MARK: - API Keys
    enum API {
        // AI API keys removed - not allowed per App Store guidelines
        // STRIPE KEYS DISABLED - Apple IAP required for digital subscriptions
        // These are preserved for future web portal or physical goods
        // static let stripePublishableKey = Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String ?? ""
        // static let stripeSecretKey = Bundle.main.object(forInfoDictionaryKey: "STRIPE_SECRET_KEY") as? String ?? ""
    }
    
    // MARK: - API Endpoints
    enum Endpoints {
        // AI endpoints removed - not using external AI APIs per App Store guidelines
        // Backend endpoints for app functionality would go here
    }
    
    // MARK: - Health Limits
    enum HealthLimits {
        // Per-group limits for medications
        static let maxMedications = 6                    // Max medications per group
        static let maxMedicationFrequency = 3            // Max times per day per medication
        
        // Per-group limits for supplements  
        static let maxSupplements = 4                    // Max supplements per group
        static let maxSupplementFrequency = 3            // Max times per day per supplement (same as medications)
        
        // Per-group limits for diet items
        static let maxDietItems = 12                     // Total diet items per group
        static let maxBreakfastItems = 3                 // Max items for breakfast
        static let maxLunchItems = 4                     // Max items for lunch
        static let maxDinnerItems = 4                    // Max items for dinner
        static let maxSnackItems = 2                     // Max items for snacks
        
        // General limits
        static let maxDailyDosesPerItem = 6              // Max doses per day for any single item
        static let maxTotalDailyReminders = 35           // Max total reminders across all items
        static let scheduleDaysAhead = 5                 // Schedule items for next 5 days
        static let minimumDoseInterval = 4               // Minimum hours between doses
        static let maxScheduleDuration = 90              // Max days for any schedule
        
        // Legacy (for backward compatibility)
        static let maximumDailyFrequency = 3             // Max times per day (legacy)
    }
    
    // MARK: - Time Settings
    enum TimeSettings {
        static let defaultBreakfastTime = (hour: 8, minute: 0)   // 8:00 AM
        static let defaultLunchTime = (hour: 14, minute: 0)      // 2:00 PM
        static let defaultDinnerTime = (hour: 19, minute: 0)     // 7:00 PM
        static let defaultBedtime = (hour: 22, minute: 0)        // 10:00 PM
    }
    
    // MARK: - Subscription
    enum Subscription {
        static let trialDurationDays = 7
        static let monthlyPrice = 8.99
        static let yearlyPrice = 70.00
        static let monthlyProductID = "com.healthguide.monthly"
        static let yearlyProductID = "com.healthguide.yearly"
        static let appleMerchantID = "merchant.com.healthguide"
    }
    
    // MARK: - Family Groups
    enum FamilyGroups {
        static let inviteCodeLength = 6
        static let inviteCodeExpiration = 24 // hours
        static let maxGroupMembers = 10
        static let adminOnlyEditing = true
    }
    
    // MARK: - UI Settings
    enum UI {
        static let minimumTouchTarget: CGFloat = 44  // Apple HIG minimum
        static let cardCornerRadius: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 12
        static let animationDuration = 0.3
        static let backdropBlur: CGFloat = 20
    }
    
    // MARK: - Cache Settings
    enum Cache {
        static let medicationSuggestionsCacheTime = 3600 // 1 hour in seconds
        static let conflictCheckCacheTime = 900          // 15 minutes
        static let maxCachedSuggestions = 100
    }
    
    // MARK: - Validation
    enum Validation {
        static let minimumMedicationNameLength = 2
        static let maximumMedicationNameLength = 100
        static let minimumDosageLength = 1
        static let maximumDosageLength = 50
        static let maximumNotesLength = 200
    }
    
    // MARK: - Biometric Auth
    enum BiometricAuth {
        static let maxRetryAttempts = 3
        static let lockoutDuration: TimeInterval = 300 // 5 minutes in seconds
        static let requireAuthOnLaunch = true
        static let allowPasscodeFallback = true
    }
    
    // MARK: - Logging
    enum Logging {
        static let enableDebugLogging = Environment.isDevelopment
        static let logHealthData = false // HIPAA compliance - never log health data
        static let maxLogFileSize = 5 * 1024 * 1024 // 5MB
    }
    
    // MARK: - Network
    enum Network {
        static let requestTimeout = 30.0
        static let maxRetryAttempts = 3
        static let retryDelay = 2.0
    }
}