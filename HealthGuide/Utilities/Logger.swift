//
//  Logger.swift
//  HealthGuide
//
//  Production-ready logging using iOS Unified Logging System
//  Zero-cost in release builds, efficient in debug
//

import Foundation
import OSLog

/// Production-ready logger using Apple's Unified Logging System
/// Provides zero-cost logging in release builds with automatic privacy protection
@available(iOS 18.0, *)
struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.healthguide.app"
    
    // MARK: - Category Loggers
    
    /// Main app lifecycle and initialization
    static let main = Logger(subsystem: subsystem, category: "main")
    
    /// UI and navigation events
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    /// Core Data and persistence
    static let data = Logger(subsystem: subsystem, category: "data")
    
    /// Network operations
    static let network = Logger(subsystem: subsystem, category: "network")
    
    /// Memory and performance
    static let performance = Logger(subsystem: subsystem, category: "performance")
    
    /// Subscription and payments
    static let subscription = Logger(subsystem: subsystem, category: "subscription")
    
    /// Notifications and badges
    static let notification = Logger(subsystem: subsystem, category: "notification")
    
    /// Authentication and security
    static let auth = Logger(subsystem: subsystem, category: "auth")
    
    /// Documents and file management
    static let document = Logger(subsystem: subsystem, category: "document")
    
    /// Audio operations
    static let audio = Logger(subsystem: subsystem, category: "audio")
    
    // MARK: - Performance Signposts
    
    /// Signpost logger for Instruments performance tracking
    static let signpost = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}

// MARK: - Convenience Extensions

extension Logger {
    
    /// Log success events
    func success(_ message: String) {
        self.info("✅ \(message)")
    }
    
    /// Log with automatic privacy for sensitive data
    func logPrivate(_ message: String, privateData: String? = nil) {
        if let data = privateData {
            self.info("\(message): \(data, privacy: .private)")
        } else {
            self.info("\(message)")
        }
    }
}