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
        static let claudeAPIKey = Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY") as? String ?? ""
        static let geminiAPIKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String ?? ""
        static let stripePublishableKey = Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String ?? ""
        static let stripeSecretKey = Bundle.main.object(forInfoDictionaryKey: "STRIPE_SECRET_KEY") as? String ?? ""
    }
    
    // MARK: - API Endpoints
    enum Endpoints {
        static let claudeBaseURL = "https://api.anthropic.com/v1"
        static let geminiBaseURL = "https://generativelanguage.googleapis.com/v1"
        static let stripeBaseURL = "https://api.stripe.com/v1"
        
        // AI Conflict Check Endpoints
        static let conflictCheckPath = "/messages"
        static let geminiConflictPath = "/models/gemini-pro:generateContent"
    }
    
    // MARK: - Health Limits
    enum HealthLimits {
        static let maximumDailyFrequency = 3  // Max times per day for any single medication/supplement
        static let scheduleDaysAhead = 5      // Schedule medications for next 5 days
        static let minimumDoseInterval = 4    // Minimum hours between doses
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