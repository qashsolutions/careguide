//
//  ScheduleEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for ScheduleEntity with CloudKit default values
//  Production-ready implementation for medication scheduling
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension ScheduleEntity {
    
    // MARK: - Schedule Frequencies
    public enum Frequency: String, CaseIterable, Sendable {
        case once = "Once"
        case daily = "Daily"
        case twiceDaily = "Twice Daily"
        case threeTimesDaily = "3 Times Daily"
        case fourTimesDaily = "4 Times Daily"
        case weekly = "Weekly"
        case biweekly = "Every 2 Weeks"
        case monthly = "Monthly"
        case asNeeded = "As Needed"
        case custom = "Custom"
        
        /// Default frequency
        static let defaultFrequency = Frequency.daily
        
        /// Number of doses per day
        var dosesPerDay: Int {
            switch self {
            case .once: return 1
            case .daily: return 1
            case .twiceDaily: return 2
            case .threeTimesDaily: return 3
            case .fourTimesDaily: return 4
            case .weekly: return 0
            case .biweekly: return 0
            case .monthly: return 0
            case .asNeeded: return 0
            case .custom: return 0
            }
        }
        
        /// Icon for UI display
        var iconName: String {
            switch self {
            case .once: return "1.circle.fill"
            case .daily: return "calendar.day.timeline.left"
            case .twiceDaily: return "2.circle.fill"
            case .threeTimesDaily: return "3.circle.fill"
            case .fourTimesDaily: return "4.circle.fill"
            case .weekly: return "calendar.badge.7"
            case .biweekly: return "calendar.badge.14"
            case .monthly: return "calendar.badge.30"
            case .asNeeded: return "questionmark.circle.fill"
            case .custom: return "gearshape.fill"
            }
        }
        
        /// Description for elder-friendly display
        var description: String {
            switch self {
            case .once: return "Take one time only"
            case .daily: return "Take once every day"
            case .twiceDaily: return "Take morning and evening"
            case .threeTimesDaily: return "Take morning, noon, and night"
            case .fourTimesDaily: return "Take 4 times throughout the day"
            case .weekly: return "Take once a week"
            case .biweekly: return "Take every 2 weeks"
            case .monthly: return "Take once a month"
            case .asNeeded: return "Take when needed"
            case .custom: return "Custom schedule"
            }
        }
    }
    
    // MARK: - Days of Week
    public enum DayOfWeek: Int, CaseIterable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7
        
        /// Short name for UI
        var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }
        
        /// Full name
        var fullName: String {
            switch self {
            case .sunday: return "Sunday"
            case .monday: return "Monday"
            case .tuesday: return "Tuesday"
            case .wednesday: return "Wednesday"
            case .thursday: return "Thursday"
            case .friday: return "Friday"
            case .saturday: return "Saturday"
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
            print("📅 ScheduleEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set start date to today if not set
        if startDate == nil {
            startDate = Calendar.current.startOfDay(for: Date())
            #if DEBUG
            print("📆 ScheduleEntity: Set start date to today")
            #endif
        }
        
        // Initialize arrays if nil
        if activeDays == nil {
            // Default to all days of the week
            activeDays = DayOfWeek.allCases.map { NSNumber(value: $0.rawValue) } as NSArray
            #if DEBUG
            print("📅 ScheduleEntity: Set active days to all week")
            #endif
        }
        
        if timePeriods == nil {
            timePeriods = NSArray()
            #if DEBUG
            print("⏰ ScheduleEntity: Initialized empty time periods")
            #endif
        }
        
        if customTimes == nil {
            customTimes = NSArray()
            #if DEBUG
            print("🕐 ScheduleEntity: Initialized empty custom times")
            #endif
        }
        
        // Validate existing data
        validateAndFixData()
        
        #if DEBUG
        print("✅ ScheduleEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes data integrity
    private func validateAndFixData() {
        // Validate frequency if set
        if let currentFrequency = frequency, !currentFrequency.isEmpty {
            let validFrequencies = Frequency.allCases.map { $0.rawValue }
            if !validFrequencies.contains(currentFrequency) {
                let oldValue = currentFrequency
                frequency = Frequency.defaultFrequency.rawValue
                
                #if DEBUG
                print("⚠️ ScheduleEntity: Invalid frequency '\(oldValue)' fixed to '\(frequency!)'")
                #endif
                
                NotificationCenter.default.post(
                    name: .coreDataEntityError,
                    object: nil,
                    userInfo: [
                        "entity": "ScheduleEntity",
                        "field": "frequency",
                        "error": "Invalid frequency value: \(oldValue)",
                        "fallbackValue": frequency!,
                        "action": "validation_fix"
                    ]
                )
            }
        }
        
        // Validate active days
        if let days = activeDays as? [NSNumber] {
            let validDays = days.filter { day in
                let dayInt = day.intValue
                return dayInt >= 1 && dayInt <= 7
            }
            
            if validDays.count != days.count {
                activeDays = validDays as NSArray
                #if DEBUG
                print("⚠️ ScheduleEntity: Fixed invalid active days")
                #endif
            }
            
            // Ensure at least one active day
            if validDays.isEmpty {
                activeDays = DayOfWeek.allCases.map { NSNumber(value: $0.rawValue) } as NSArray
                #if DEBUG
                print("⚠️ ScheduleEntity: No active days, defaulting to all days")
                #endif
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Set frequency with validation
    public func setFrequency(_ newFrequency: Frequency) {
        frequency = newFrequency.rawValue
        #if DEBUG
        print("📊 ScheduleEntity: Updated frequency to \(newFrequency.rawValue)")
        #endif
    }
    
    /// Get frequency as enum
    public var scheduleFrequency: Frequency? {
        guard let frequency = frequency else { return nil }
        return Frequency(rawValue: frequency)
    }
    
    /// Check if schedule is active today
    public var isActiveToday: Bool {
        let today = Calendar.current.component(.weekday, from: Date())
        let activeDayNumbers = (activeDays as? [NSNumber]) ?? []
        return activeDayNumbers.contains(NSNumber(value: today))
    }
    
    /// Check if schedule has ended
    public var hasEnded: Bool {
        guard let endDate = endDate else { return false }
        return endDate < Date()
    }
    
    /// Check if schedule is currently active
    public var isActive: Bool {
        guard let start = startDate else { return false }
        
        // Check if started
        if start > Date() {
            return false
        }
        
        // Check if ended
        if hasEnded {
            return false
        }
        
        return true
    }
    
    /// Get active days as DayOfWeek array
    public var activeDaysOfWeek: [DayOfWeek] {
        guard let dayNumbers = activeDays as? [NSNumber] else { return [] }
        return dayNumbers.compactMap { DayOfWeek(rawValue: $0.intValue) }
    }
    
    /// Set active days from DayOfWeek array
    public func setActiveDays(_ days: [DayOfWeek]) {
        activeDays = days.map { NSNumber(value: $0.rawValue) } as NSArray
        #if DEBUG
        print("📅 ScheduleEntity: Updated active days")
        #endif
    }
    
    /// Get time periods as string array
    public var timePeriodsArray: [String] {
        return (timePeriods as? [String]) ?? []
    }
    
    /// Set time periods from string array
    public func setTimePeriods(_ periods: [String]) {
        timePeriods = periods as NSArray
        #if DEBUG
        print("⏰ ScheduleEntity: Updated time periods: \(periods)")
        #endif
    }
    
    /// Get custom times as Date array
    public var customTimesArray: [Date] {
        return (customTimes as? [Date]) ?? []
    }
    
    /// Set custom times from Date array
    public func setCustomTimes(_ times: [Date]) {
        customTimes = times as NSArray
        #if DEBUG
        print("🕐 ScheduleEntity: Updated custom times")
        #endif
    }
    
    /// Get formatted schedule description
    public var scheduleDescription: String {
        guard let freq = scheduleFrequency else { return "No schedule" }
        
        var description = freq.description
        
        // Add active days for non-daily schedules
        if freq != .daily && freq != .once {
            let days = activeDaysOfWeek.map { $0.shortName }.joined(separator: ", ")
            if !days.isEmpty && days != "Sun, Mon, Tue, Wed, Thu, Fri, Sat" {
                description += " on \(days)"
            }
        }
        
        // Add time information
        if !timePeriodsArray.isEmpty {
            let times = timePeriodsArray.joined(separator: ", ")
            description += " at \(times)"
        } else if !customTimesArray.isEmpty {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let times = customTimesArray.map { formatter.string(from: $0) }.joined(separator: ", ")
            description += " at \(times)"
        }
        
        return description
    }
    
    /// Get next dose time
    public func nextDoseTime(after date: Date = Date()) -> Date? {
        guard isActive else { return nil }
        
        // For as-needed, return nil
        if scheduleFrequency == .asNeeded {
            return nil
        }
        
        // Get today's day of week
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        
        // Check if today is active
        let activeDayNumbers = (activeDays as? [NSNumber]) ?? []
        
        // Find next active day
        var daysToAdd = 0
        for i in 0...7 {
            let checkDay = ((weekday - 1 + i) % 7) + 1
            if activeDayNumbers.contains(NSNumber(value: checkDay)) {
                daysToAdd = i
                break
            }
        }
        
        // Get the target date
        var targetDate = calendar.date(byAdding: .day, value: daysToAdd, to: date) ?? date
        targetDate = calendar.startOfDay(for: targetDate)
        
        // Add time component
        if let firstCustomTime = customTimesArray.first {
            let timeComponents = calendar.dateComponents([.hour, .minute], from: firstCustomTime)
            targetDate = calendar.date(byAdding: timeComponents, to: targetDate) ?? targetDate
        }
        
        // If the calculated time is in the past and it's today, find next time slot
        if targetDate <= date && daysToAdd == 0 {
            // Try to find next time slot today
            for customTime in customTimesArray {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: customTime)
                if let nextTime = calendar.date(byAdding: timeComponents, to: calendar.startOfDay(for: date)),
                   nextTime > date {
                    return nextTime
                }
            }
            
            // No more times today, go to next active day
            return nextDoseTime(after: calendar.date(byAdding: .day, value: 1, to: date) ?? date)
        }
        
        return targetDate
    }
    
    /// Get days remaining in schedule
    public var daysRemaining: Int? {
        guard let endDate = endDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day
        return max(0, days ?? 0)
    }
    
    /// Get associated item name
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
}