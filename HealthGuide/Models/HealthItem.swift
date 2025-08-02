//
//  HealthItem.swift
//  HealthGuide
//
//  Base protocol defines structure for all health data
//  Shared behavior for medications, supplements, and diet
//

import Foundation
import SwiftUI

@available(iOS 18.0, *)
protocol HealthItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID { get }
    var name: String { get set }
    var notes: String? { get set }
    var schedule: Schedule { get set }
    var isActive: Bool { get set }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    
    // Computed properties
    var itemType: HealthItemType { get }
    var displayName: String { get }
    var nextDoseTime: Date? { get }
}

// MARK: - Health Item Type
@available(iOS 18.0, *)
enum HealthItemType: String, CaseIterable, Codable, Sendable {
    case medication = "Medication"
    case supplement = "Supplement"
    case diet = "Diet"
    
    var displayName: String {
        switch self {
        case .medication:
            return AppStrings.HealthTypes.medication
        case .supplement:
            return AppStrings.HealthTypes.supplement
        case .diet:
            return AppStrings.HealthTypes.diet
        }
    }
    
    var headerColor: Color {
        switch self {
        case .medication:
            return AppTheme.Colors.medicationBlue
        case .supplement:
            return AppTheme.Colors.supplementGreen
        case .diet:
            return AppTheme.Colors.dietBlue
        }
    }
    
    var iconName: String {
        switch self {
        case .medication:
            return "pills.fill"
        case .supplement:
            return "leaf.fill"
        case .diet:
            return "fork.knife"
        }
    }
    
    var color: Color {
        return headerColor
    }
}

// MARK: - Default Implementation
@available(iOS 18.0, *)
extension HealthItem {
    var displayName: String {
        return name
    }
    
    var nextDoseTime: Date? {
        guard isActive else { return nil }
        return schedule.nextDoseTime(from: Date())
    }
    
    func isScheduledForToday() -> Bool {
        guard isActive else { return false }
        return schedule.isScheduledForDate(Date())
    }
    
    func dosesForToday() -> [ScheduledDose] {
        guard isActive else { return [] }
        return schedule.dosesForDate(Date())
    }
    
    func validate() throws {
        // Name validation
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= Configuration.Validation.minimumMedicationNameLength else {
            throw AppError.nameTooShort(minimum: Configuration.Validation.minimumMedicationNameLength)
        }
        guard trimmedName.count <= Configuration.Validation.maximumMedicationNameLength else {
            throw AppError.nameTooLong(maximum: Configuration.Validation.maximumMedicationNameLength)
        }
        
        // Schedule validation
        try schedule.validate()
        
        // Notes validation if present
        if let notes = notes, notes.count > Configuration.Validation.maximumNotesLength {
            throw AppError.nameTooLong(maximum: Configuration.Validation.maximumNotesLength)
        }
    }
}

// MARK: - Scheduled Dose
@available(iOS 18.0, *)
struct ScheduledDose: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let time: Date
    let period: TimePeriod
    var isTaken: Bool = false
    var takenAt: Date?
    
    init(id: UUID = UUID(), time: Date, period: TimePeriod, isTaken: Bool = false, takenAt: Date? = nil) {
        self.id = id
        self.time = time
        self.period = period
        self.isTaken = isTaken
        self.takenAt = takenAt
    }
    
    var isPastDue: Bool {
        !isTaken && time < Date()
    }
    
    var isCurrent: Bool {
        let now = Date()
        let calendar = Calendar.current
        let hoursDiff = calendar.dateComponents([.hour], from: time, to: now).hour ?? 0
        return abs(hoursDiff) <= 1 && !isTaken
    }
    
    var isUpcoming: Bool {
        !isTaken && time > Date()
    }
}

// MARK: - Time Period
@available(iOS 18.0, *)
enum TimePeriod: String, CaseIterable, Codable, Sendable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case bedtime = "Bedtime"
    case custom = "Custom"
    
    var displayName: String {
        switch self {
        case .breakfast:
            return AppStrings.TimePeriods.breakfast
        case .lunch:
            return AppStrings.TimePeriods.lunch
        case .dinner:
            return AppStrings.TimePeriods.dinner
        case .bedtime:
            return AppStrings.TimePeriods.bedtime
        case .custom:
            return "Custom"
        }
    }
    
    var defaultTime: (hour: Int, minute: Int) {
        switch self {
        case .breakfast:
            return Configuration.TimeSettings.defaultBreakfastTime
        case .lunch:
            return Configuration.TimeSettings.defaultLunchTime
        case .dinner:
            return Configuration.TimeSettings.defaultDinnerTime
        case .bedtime:
            return Configuration.TimeSettings.defaultBedtime
        case .custom:
            return (9, 0)  // 9:00 AM default for custom
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .breakfast: return 1
        case .lunch: return 2
        case .dinner: return 3
        case .bedtime: return 4
        case .custom: return 5
        }
    }
    
    var iconName: String {
        switch self {
        case .breakfast:
            return "sun.max.fill"
        case .lunch:
            return "sun.max"
        case .dinner:
            return "moon.fill"
        case .bedtime:
            return "bed.double.fill"
        case .custom:
            return "clock.fill"
        }
    }
}