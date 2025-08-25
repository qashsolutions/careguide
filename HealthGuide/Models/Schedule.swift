//
//  Schedule.swift
//  HealthGuide
//
//  Timing and frequency model used by all health items
//  Configurable times, 3x daily limit enforcement
//

import Foundation

@available(iOS 18.0, *)
struct Schedule: Codable, Hashable, Sendable {
    var frequency: Frequency
    var timePeriods: [TimePeriod]
    var customTimes: [Date]
    var startDate: Date
    var endDate: Date?
    var activeDays: Set<Date>  // Specific days item is scheduled
    
    init(
        frequency: Frequency = .once,
        timePeriods: [TimePeriod] = [.breakfast],
        customTimes: [Date] = [],
        startDate: Date = Date(),
        endDate: Date? = nil,
        activeDays: Set<Date> = []
    ) {
        self.frequency = frequency
        self.timePeriods = timePeriods
        self.customTimes = customTimes
        self.startDate = startDate
        self.endDate = endDate
        self.activeDays = activeDays.isEmpty ? Schedule.generateDefaultActiveDays(from: startDate) : activeDays
    }
}

// MARK: - Frequency
@available(iOS 18.0, *)
extension Schedule {
    enum Frequency: String, CaseIterable, Codable {
        case once = "Once"
        case twice = "Twice"
        case threeTimesDaily = "Three times"
        
        var displayName: String {
            switch self {
            case .once:
                return AppStrings.Frequency.once
            case .twice:
                return AppStrings.Frequency.twice
            case .threeTimesDaily:
                return AppStrings.Frequency.threeTimes
            }
        }
        
        var count: Int {
            switch self {
            case .once: return 1
            case .twice: return 2
            case .threeTimesDaily: return 3
            }
        }
    }
}

// MARK: - Schedule Logic
@available(iOS 18.0, *)
extension Schedule {
    func validate() throws {
        // Ensure frequency doesn't exceed daily limit
        guard frequency.count <= Configuration.HealthLimits.maximumDailyFrequency else {
            throw AppError.medicationLimitExceeded(
                current: frequency.count,
                maximum: Configuration.HealthLimits.maximumDailyFrequency
            )
        }
        
        // Ensure time periods match frequency
        let totalTimes = timePeriods.count + customTimes.count
        guard totalTimes == frequency.count else {
            throw AppError.invalidSchedule(
                reason: "Selected \(frequency.displayName) but configured \(totalTimes) time periods"
            )
        }
        
        // Ensure start date is not in the past
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scheduleStart = calendar.startOfDay(for: startDate)
        guard scheduleStart >= today else {
            throw AppError.invalidSchedule(reason: "Cannot schedule for past dates")
        }
        
        // Validate minimum dose interval
        let allTimes = getAllScheduledTimes(for: Date())
        // Only validate if we have at least 2 doses to compare
        if allTimes.count >= 2 {
            for i in 1..<allTimes.count {
                let interval = allTimes[i].timeIntervalSince(allTimes[i-1]) / 3600  // Convert to hours
                guard interval >= Double(Configuration.HealthLimits.minimumDoseInterval) else {
                    throw AppError.invalidSchedule(
                        reason: "Doses must be at least \(Configuration.HealthLimits.minimumDoseInterval) hours apart"
                    )
                }
            }
        }
    }
    
    func isScheduledForDate(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let checkDate = calendar.startOfDay(for: date)
        
        // Check if date is within schedule range
        guard checkDate >= calendar.startOfDay(for: startDate) else { 
            #if DEBUG
            print("🗓️ Schedule: Date \(date) is before start date \(startDate)")
            #endif
            return false 
        }
        if let endDate = endDate, checkDate > calendar.startOfDay(for: endDate) { 
            #if DEBUG
            print("🗓️ Schedule: Date \(date) is after end date \(endDate)")
            #endif
            return false 
        }
        
        // Check if date is in active days
        let isActive = activeDays.contains { calendar.isDate($0, inSameDayAs: date) }
        
        #if DEBUG
        print("🗓️ Schedule: Checking date \(date)")
        print("   Active days: \(activeDays.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) })")
        print("   Is scheduled: \(isActive)")
        #endif
        
        return isActive
    }
    
    func dosesForDate(_ date: Date) -> [ScheduledDose] {
        guard isScheduledForDate(date) else { return [] }
        
        var doses: [ScheduledDose] = []
        let calendar = Calendar.current
        
        // Add doses for each time period
        for (index, period) in timePeriods.enumerated() where index < frequency.count {
            let time = calendar.date(bySettingHour: period.defaultTime.hour,
                                   minute: period.defaultTime.minute,
                                   second: 0,
                                   of: date) ?? date
            doses.append(ScheduledDose(time: time, period: period))
        }
        
        // Add custom time doses
        for customTime in customTimes {
            let components = calendar.dateComponents([.hour, .minute], from: customTime)
            if let time = calendar.date(bySettingHour: components.hour ?? 0,
                                      minute: components.minute ?? 0,
                                      second: 0,
                                      of: date) {
                doses.append(ScheduledDose(time: time, period: .custom))
            }
        }
        
        // Sort by time
        return doses.sorted { $0.time < $1.time }
    }
    
    func nextDoseTime(from date: Date) -> Date? {
        let calendar = Calendar.current
        var checkDate = calendar.startOfDay(for: date)
        
        // Check up to 7 days ahead
        for _ in 0..<7 {
            let doses = dosesForDate(checkDate)
            for dose in doses where !dose.isTaken && dose.time > date {
                return dose.time
            }
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate) ?? checkDate
        }
        
        return nil
    }
    
    /// Generate dose times for a specific date
    /// - Parameter date: The date to generate dose times for
    /// - Returns: Array of dates representing dose times
    func generateDoseTimes(for date: Date) -> [Date] {
        guard isScheduledForDate(date) else { return [] }
        
        let calendar = Calendar.current
        var doseTimes: [Date] = []
        
        // Add times for each time period
        for (index, period) in timePeriods.enumerated() where index < frequency.count {
            if let time = calendar.date(bySettingHour: period.defaultTime.hour,
                                       minute: period.defaultTime.minute,
                                       second: 0,
                                       of: date) {
                doseTimes.append(time)
            }
        }
        
        // Add custom times
        for customTime in customTimes {
            let components = calendar.dateComponents([.hour, .minute], from: customTime)
            if let time = calendar.date(bySettingHour: components.hour ?? 0,
                                      minute: components.minute ?? 0,
                                      second: 0,
                                      of: date) {
                doseTimes.append(time)
            }
        }
        
        return doseTimes.sorted()
    }
    
    private func getAllScheduledTimes(for date: Date) -> [Date] {
        dosesForDate(date).map { $0.time }.sorted()
    }
}

// MARK: - Helper Methods
@available(iOS 18.0, *)
extension Schedule {
    static func generateDefaultActiveDays(from startDate: Date) -> Set<Date> {
        var days = Set<Date>()
        let calendar = Calendar.current
        
        // Generate for next 5 days by default
        for dayOffset in 0..<Configuration.HealthLimits.scheduleDaysAhead {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                days.insert(calendar.startOfDay(for: date))
            }
        }
        
        return days
    }
    
    mutating func setActiveDaysForNext(_ numberOfDays: Int) {
        activeDays = Schedule.generateDefaultActiveDays(from: startDate)
        if numberOfDays < Configuration.HealthLimits.scheduleDaysAhead {
            // Remove days beyond requested
            let calendar = Calendar.current
            activeDays = activeDays.filter { date in
                let daysDiff = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
                return daysDiff < numberOfDays
            }
        }
    }
}