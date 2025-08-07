//
//  Logger.swift
//  HealthGuide
//
//  Efficient logging utility that reduces overhead in production
//

import Foundation
import os.log

/// Lightweight logger that eliminates overhead in production builds
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "HealthGuide"
    
    // Create different loggers for different categories
    private static let ui = OSLog(subsystem: subsystem, category: "UI")
    private static let data = OSLog(subsystem: subsystem, category: "Data")
    private static let network = OSLog(subsystem: subsystem, category: "Network")
    private static let memory = OSLog(subsystem: subsystem, category: "Memory")
    
    /// Log UI-related events
    static func logUI(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: ui, type: .debug, message)
        #endif
    }
    
    /// Log data/Core Data events
    static func logData(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: data, type: .debug, message)
        #endif
    }
    
    /// Log network events
    static func logNetwork(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: network, type: .debug, message)
        #endif
    }
    
    /// Log memory events
    static func logMemory(_ message: String) {
        #if DEBUG
        os_log("%{public}@", log: memory, type: .debug, message)
        #endif
    }
    
    /// Log errors (always logged, even in production)
    static func logError(_ message: String) {
        os_log("%{public}@", log: .default, type: .error, message)
    }
}