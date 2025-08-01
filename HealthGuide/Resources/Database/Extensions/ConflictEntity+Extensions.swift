//
//  ConflictEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for ConflictEntity with CloudKit default values
//  Production-ready implementation for medication conflict tracking
//

import Foundation
import CoreData
import SwiftUI

// MARK: - Notification Names
extension Notification.Name {
    static let coreDataEntityError = Notification.Name("coreDataEntityError")
}

@available(iOS 18.0, *)
extension ConflictEntity {
    
    // MARK: - Severity Levels
    public enum SeverityLevel: String, CaseIterable, Sendable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case critical = "Critical"
        
        /// Default severity for new conflicts
        static let defaultSeverity = SeverityLevel.medium
        
        /// Color representation for UI
        var colorName: String {
            switch self {
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "orange"
            case .critical: return "red"
            }
        }
        
        /// Priority for sorting (higher number = more severe)
        var priority: Int {
            switch self {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            case .critical: return 4
            }
        }
    }
    
    // MARK: - awakeFromInsert
    /// Called when entity is first inserted into context
    /// Sets default values for required fields to ensure CloudKit compatibility
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Generate unique ID
        if id == nil {
            id = UUID()
            #if DEBUG
            print("⚠️ ConflictEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set empty strings for required text fields
        if conflictDescription == nil {
            conflictDescription = ""
            #if DEBUG
            print("📝 ConflictEntity: Set empty conflict description")
            #endif
        }
        
        if medicationA == nil {
            medicationA = ""
            #if DEBUG
            print("💊 ConflictEntity: Set empty medicationA")
            #endif
        }
        
        if medicationB == nil {
            medicationB = ""
            #if DEBUG
            print("💊 ConflictEntity: Set empty medicationB")
            #endif
        }
        
        // Set default severity
        if severity == nil {
            severity = SeverityLevel.defaultSeverity.rawValue
            #if DEBUG
            print("🚨 ConflictEntity: Set default severity: \(severity!)")
            #endif
        }
        
        // Validate severity value
        validateAndFixSeverity()
        
        #if DEBUG
        print("✅ ConflictEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes severity value if corrupted
    private func validateAndFixSeverity() {
        guard let currentSeverity = severity else { return }
        
        // Check if severity is valid
        let validSeverities = SeverityLevel.allCases.map { $0.rawValue }
        if !validSeverities.contains(currentSeverity) {
            let oldValue = currentSeverity
            severity = SeverityLevel.defaultSeverity.rawValue
            
            #if DEBUG
            print("⚠️ ConflictEntity: Invalid severity '\(oldValue)' fixed to '\(severity!)'")
            #endif
            
            // Post notification for error tracking
            NotificationCenter.default.post(
                name: .coreDataEntityError,
                object: nil,
                userInfo: [
                    "entity": "ConflictEntity",
                    "field": "severity",
                    "error": "Invalid severity value: \(oldValue)",
                    "fallbackValue": severity!,
                    "action": "validation_fix"
                ]
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Update severity with validation
    public func setSeverity(_ level: SeverityLevel) {
        severity = level.rawValue
        checkedAt = Date()
        
        #if DEBUG
        print("🚨 ConflictEntity: Updated severity to \(level.rawValue)")
        #endif
    }
    
    /// Get severity as enum
    public var severityLevel: SeverityLevel? {
        guard let severity = severity else { return nil }
        return SeverityLevel(rawValue: severity)
    }
    
    /// Get severity color for SwiftUI
    public var severityColor: Color {
        return Color(severityLevel?.colorName ?? "gray")
    }
    
    /// Check if conflict involves specific medication
    public func involvesMedication(named name: String) -> Bool {
        let searchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let medA = (medicationA ?? "").lowercased()
        let medB = (medicationB ?? "").lowercased()
        
        return medA.contains(searchName) || medB.contains(searchName)
    }
    
    /// Update conflict check timestamp and checker
    public func markAsChecked(by checker: String) {
        checkedAt = Date()
        checkedBy = checker
        
        #if DEBUG
        print("✓ ConflictEntity: Marked as checked by \(checker)")
        #endif
    }
    
    /// Check if conflict needs review (older than 30 days)
    public var needsReview: Bool {
        guard let lastChecked = checkedAt else { return true }
        let daysSinceCheck = Calendar.current.dateComponents([.day], 
                                                            from: lastChecked, 
                                                            to: Date()).day ?? 0
        return daysSinceCheck > 30
    }
    
    /// Format conflict for display
    public var displayTitle: String {
        guard let medA = medicationA, !medA.isEmpty,
              let medB = medicationB, !medB.isEmpty else {
            return "Unnamed Conflict"
        }
        return "\(medA) + \(medB)"
    }
}
