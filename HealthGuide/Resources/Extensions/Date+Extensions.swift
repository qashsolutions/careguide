//
//  Date+Extensions.swift
//  HealthGuide
//
//  Date utilities needed by schedule calculations
//  Elder-friendly date formatting and time helpers
//

import Foundation

@available(iOS 18.0, *)
extension Date {
    
    // MARK: - Display Helpers (Thread-Safe FormatStyle API)
    var timeString: String {
        self.formatted(date: .omitted, time: .shortened)
    }
    
    var dateString: String {
        self.formatted(date: .abbreviated, time: .omitted)
    }
    
    var fullDateTimeString: String {
        self.formatted(date: .abbreviated, time: .shortened)
    }
    
    var dayOfWeek: String {
        self.formatted(.dateTime.weekday(.wide))  // Monday, Tuesday, etc.
    }
    
    var monthDay: String {
        self.formatted(.dateTime.month(.abbreviated).day())  // Jul 24
    }
    
    // MARK: - Elder-Friendly Relative Formatting
    var relativeTimeString: String {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if it's today
        if calendar.isDateInToday(self) {
            let components = calendar.dateComponents([.hour, .minute], from: now, to: self)
            
            if let hours = components.hour, let minutes = components.minute {
                if hours == 0 && minutes >= 0 && minutes < 60 {
                    if minutes == 0 {
                        return "Now"
                    } else if minutes == 1 {
                        return "In 1 minute"
                    } else {
                        return "In \(minutes) minutes"
                    }
                } else if hours == 1 && minutes >= 0 {
                    return "In 1 hour"
                } else if hours > 1 {
                    return "In \(hours) hours"
                } else if hours == -1 {
                    return "1 hour ago"
                } else if hours < -1 {
                    return "\(-hours) hours ago"
                } else if minutes < 0 {
                    return "\(-minutes) minutes ago"
                }
            }
            
            return "Today at \(timeString)"
        }
        
        // Check if it's tomorrow
        if calendar.isDateInTomorrow(self) {
            return "Tomorrow at \(timeString)"
        }
        
        // Check if it's yesterday
        if calendar.isDateInYesterday(self) {
            return "Yesterday at \(timeString)"
        }
        
        // For other dates, show day and time
        let daysApart = calendar.dateComponents([.day], from: now, to: self).day ?? 0
        
        if daysApart > 0 && daysApart < 7 {
            return "\(dayOfWeek) at \(timeString)"
        } else if daysApart < 0 && daysApart > -7 {
            return "Last \(dayOfWeek) at \(timeString)"
        }
        
        // Default to full date
        return fullDateTimeString
    }
    
    // MARK: - Schedule Helpers
    func isSameDay(as date: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: date)
    }
    
    func startOfDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }
    
    func endOfDay() -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay()) ?? self
    }
    
    func addingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
    
    func addingHours(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: hours, to: self) ?? self
    }
    
    func timeOnDate(_ date: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: self)
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                           minute: timeComponents.minute ?? 0,
                           second: timeComponents.second ?? 0,
                           of: date) ?? date
    }
    
    // MARK: - Time Period Helpers
    func isInMorning() -> Bool {
        let hour = Calendar.current.component(.hour, from: self)
        return hour >= 5 && hour < 12
    }
    
    func isInAfternoon() -> Bool {
        let hour = Calendar.current.component(.hour, from: self)
        return hour >= 12 && hour < 17
    }
    
    func isInEvening() -> Bool {
        let hour = Calendar.current.component(.hour, from: self)
        return hour >= 17 && hour < 21
    }
    
    func isAtNight() -> Bool {
        let hour = Calendar.current.component(.hour, from: self)
        return hour >= 21 || hour < 5
    }
    
    // MARK: - Schedule Generation
    static func generateDatesForNext(_ days: Int, from startDate: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        
        for dayOffset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                dates.append(calendar.startOfDay(for: date))
            }
        }
        
        return dates
    }
    
    // MARK: - Age Calculation
    func ageInDays(from date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: self, to: date)
        return abs(components.day ?? 0)
    }
    
    func ageInHours(from date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: self, to: date)
        return abs(components.hour ?? 0)
    }
    
    // MARK: - Validation
    func isInFuture() -> Bool {
        self > Date()
    }
    
    func isInPast() -> Bool {
        self < Date()
    }
    
    func isWithinNext24Hours() -> Bool {
        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)
        return self >= now && self <= tomorrow
    }
}