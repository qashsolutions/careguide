//
//  DoseEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for DoseEntity with CloudKit default values
//  Production-ready implementation for medication dose tracking
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension DoseEntity {
    
    // MARK: - Time Periods
    public enum TimePeriod: String, CaseIterable, Sendable {
        case earlyMorning = "Early Morning"
        case breakfast = "Breakfast"
        case midMorning = "Mid Morning"
        case lunch = "Lunch"
        case afternoon = "Afternoon"
        case dinner = "Dinner"
        case bedtime = "Bedtime"
        case asNeeded = "As Needed"
        
        /// Default period
        static let defaultPeriod = TimePeriod.breakfast
        
        /// Typical time for period
        var typicalTime: String {
            switch self {
            case .earlyMorning: return "6:00 AM"
            case .breakfast: return "8:00 AM"
            case .midMorning: return "10:00 AM"
            case .lunch: return "12:00 PM"
            case .afternoon: return "3:00 PM"
            case .dinner: return "6:00 PM"
            case .bedtime: return "9:00 PM"
            case .asNeeded: return "Any time"
            }
        }
        
        /// Icon for UI display
        var iconName: String {
            switch self {
            case .earlyMorning: return "sunrise.fill"
            case .breakfast: return "sun.max.fill"
            case .midMorning: return "sun.min.fill"
            case .lunch: return "sun.and.horizon.fill"
            case .afternoon: return "cloud.sun.fill"
            case .dinner: return "sunset.fill"
            case .bedtime: return "moon.stars.fill"
            case .asNeeded: return "clock.fill"
            }
        }
        
        /// Sort order
        var sortOrder: Int {
            switch self {
            case .earlyMorning: return 0
            case .breakfast: return 1
            case .midMorning: return 2
            case .lunch: return 3
            case .afternoon: return 4
            case .dinner: return 5
            case .bedtime: return 6
            case .asNeeded: return 7
            }
        }
    }
    
    // MARK: - Dose Status
    public enum DoseStatus {
        case pending
        case taken
        case missed
        case skipped
        
        /// Color for status
        var color: Color {
            switch self {
            case .pending: return .orange
            case .taken: return .green
            case .missed: return .red
            case .skipped: return .gray
            }
        }
        
        /// Icon for status
        var iconName: String {
            switch self {
            case .pending: return "clock.fill"
            case .taken: return "checkmark.circle.fill"
            case .missed: return "exclamationmark.triangle.fill"
            case .skipped: return "minus.circle.fill"
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
            print("💊 DoseEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set scheduled time to current date/time if not set
        if scheduledTime == nil {
            scheduledTime = Date()
            #if DEBUG
            print("⏰ DoseEntity: Set scheduled time to now")
            #endif
        }
        
        // Set default taken status
        // isTaken is non-optional Bool, always set default
        isTaken = false
        #if DEBUG
        print("❌ DoseEntity: Set default isTaken to false")
        #endif
        
        // Validate existing data
        validateAndFixData()
        
        #if DEBUG
        print("✅ DoseEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes data integrity
    private func validateAndFixData() {
        // Validate period if set
        if let currentPeriod = period, !currentPeriod.isEmpty {
            let validPeriods = TimePeriod.allCases.map { $0.rawValue }
            if !validPeriods.contains(currentPeriod) {
                let oldValue = currentPeriod
                period = TimePeriod.defaultPeriod.rawValue
                
                #if DEBUG
                print("⚠️ DoseEntity: Invalid period '\(oldValue)' fixed to '\(period!)'")
                #endif
                
                NotificationCenter.default.post(
                    name: .coreDataEntityError,
                    object: nil,
                    userInfo: [
                        "entity": "DoseEntity",
                        "field": "period",
                        "error": "Invalid period value: \(oldValue)",
                        "fallbackValue": period!,
                        "action": "validation_fix"
                    ]
                )
            }
        }
        
        // Ensure scheduled time is not in the distant past
        if let scheduled = scheduledTime {
            let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            if scheduled < oneYearAgo {
                scheduledTime = Date()
                #if DEBUG
                print("⚠️ DoseEntity: Fixed scheduled time that was too far in the past")
                #endif
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Set period with validation
    public func setPeriod(_ newPeriod: TimePeriod) {
        period = newPeriod.rawValue
        #if DEBUG
        print("⏰ DoseEntity: Updated period to \(newPeriod.rawValue)")
        #endif
    }
    
    /// Get period as enum
    public var timePeriod: TimePeriod? {
        guard let period = period else { return nil }
        return TimePeriod(rawValue: period)
    }
    
    /// Get period icon
    public var periodIconName: String {
        return timePeriod?.iconName ?? "clock.fill"
    }
    
    /// Mark dose as taken
    public func markAsTaken(at time: Date = Date()) {
        isTaken = true
        takenAt = time
        
        #if DEBUG
        print("✅ DoseEntity: Marked as taken at \(time)")
        #endif
        
        // Post notification for tracking
        NotificationCenter.default.post(
            name: Notification.Name("DoseTaken"),
            object: nil,
            userInfo: [
                "doseID": id ?? UUID(),
                "takenAt": time,
                "scheduledTime": scheduledTime ?? Date()
            ]
        )
    }
    
    /// Mark dose as skipped
    public func markAsSkipped(reason: String? = nil) {
        isTaken = false
        if let reason = reason {
            notes = reason
        }
        
        #if DEBUG
        print("⏭️ DoseEntity: Marked as skipped")
        #endif
    }
    
    /// Get dose status
    public var status: DoseStatus {
        if isTaken {
            return .taken
        }
        
        guard let scheduled = scheduledTime else { return .pending }
        
        let now = Date()
        if scheduled > now {
            return .pending
        } else {
            // Consider dose missed if more than 2 hours past scheduled time
            let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: now) ?? now
            return scheduled < twoHoursAgo ? .missed : .pending
        }
    }
    
    /// Get status color
    public var statusColor: Color {
        return status.color
    }
    
    /// Get status icon
    public var statusIconName: String {
        return status.iconName
    }
    
    /// Check if dose is overdue
    public var isOverdue: Bool {
        guard let scheduled = scheduledTime, !isTaken else { return false }
        return scheduled < Date()
    }
    
    /// Get time until dose
    public var timeUntilDose: TimeInterval? {
        guard let scheduled = scheduledTime else { return nil }
        return scheduled.timeIntervalSince(Date())
    }
    
    /// Get formatted time until dose
    public var formattedTimeUntil: String {
        guard let timeInterval = timeUntilDose else { return "Unknown" }
        
        if timeInterval < 0 {
            // Overdue
            let hours = Int(abs(timeInterval) / 3600)
            let minutes = Int((abs(timeInterval).truncatingRemainder(dividingBy: 3600)) / 60)
            
            if hours > 0 {
                return "\(hours)h \(minutes)m overdue"
            } else {
                return "\(minutes)m overdue"
            }
        } else {
            // Upcoming
            let hours = Int(timeInterval / 3600)
            let minutes = Int((timeInterval.truncatingRemainder(dividingBy: 3600)) / 60)
            
            if hours > 0 {
                return "in \(hours)h \(minutes)m"
            } else {
                return "in \(minutes)m"
            }
        }
    }
    
    /// Get associated item name (medication, supplement, or diet)
    public var itemName: String {
        if let medication = medication {
            return medication.name ?? "Unknown Medication"
        } else if let supplement = supplement {
            return supplement.name ?? "Unknown Supplement"
        } else if let diet = diet {
            return diet.name ?? "Unknown Diet Item"
        }
        return "Unknown Item"
    }
    
    /// Get associated item dosage
    public var itemDosage: String {
        if let medication = medication {
            let dosage = medication.dosage ?? ""
            let unit = medication.unit ?? ""
            return "\(dosage) \(unit)".trimmingCharacters(in: .whitespaces)
        } else if let supplement = supplement {
            return supplement.formattedDosage
        }
        return ""
    }
    
    /// Check if dose is for today
    public var isToday: Bool {
        guard let scheduled = scheduledTime else { return false }
        return Calendar.current.isDateInToday(scheduled)
    }
    
    /// Get formatted scheduled time
    public var formattedScheduledTime: String {
        guard let scheduled = scheduledTime else { return "Not scheduled" }
        
        let formatter = DateFormatter()
        if isToday {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: scheduled)
    }
    
    /// Get formatted taken time
    public var formattedTakenTime: String? {
        guard let taken = takenAt else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Taken at \(formatter.string(from: taken))"
    }
    
    /// Calculate adherence delay (how late the dose was taken)
    public var adherenceDelay: TimeInterval? {
        guard let scheduled = scheduledTime,
              let taken = takenAt,
              isTaken else { return nil }
        
        return taken.timeIntervalSince(scheduled)
    }
    
    /// Check if dose was taken on time (within 30 minutes)
    public var wasTakenOnTime: Bool {
        guard let delay = adherenceDelay else { return false }
        return abs(delay) <= 1800 // 30 minutes
    }
}