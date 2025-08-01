//
//  CheckScheduleIntent.swift
//  HealthGuide
//
//  Siri intent for checking medication schedule
//

import AppIntents
import SwiftUI
import CoreData

// Data transfer struct for Swift 6 compliance
@available(iOS 18.0, *)
struct MedicationScheduleInfo: Sendable {
    let name: String
    let dosage: String
    let timePeriods: [String]
}

@available(iOS 18.0, *)
struct CheckScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Medication Schedule"
    static let description = IntentDescription("Check what medications you need to take today")
    
    // Parameters
    @Parameter(title: "Time Period", default: "today")
    var timePeriod: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Check medications for \(\.$timePeriod)")
    }
    
    // Main execution
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext
        
        // Get date range for the time period
        let dateRange = getDateRange(for: timePeriod)
        
        // Fetch medications with schedules
        let medications = try await context.perform {
            try fetchScheduledMedications(
                from: dateRange.start,
                to: dateRange.end,
                context: context
            )
        }
        
        if medications.isEmpty {
            return .result(
                value: "No medications scheduled",
                dialog: "You don't have any medications scheduled for \(timePeriod)."
            )
        }
        
        // Group medications by time
        let schedule = groupMedicationsByTime(medications)
        let responseText = formatScheduleResponse(schedule, for: timePeriod)
        
        return .result(
            value: responseText,
            dialog: IntentDialog(stringLiteral: responseText)
        )
    }
    
    // Helper methods
    private func fetchScheduledMedications(
        from startDate: Date,
        to endDate: Date,
        context: NSManagedObjectContext
    ) throws -> [MedicationScheduleInfo] {
        let request = MedicationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "schedule != nil")
        
        let allMedications = try context.fetch(request)
        
        // Filter medications that have schedules for the date range and convert to Sendable struct
        return allMedications.compactMap { medication in
            guard let schedule = medication.schedule else { return nil }
            
            // Check if schedule is active on this day
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: startDate)
            
            // Check if this weekday is in activeDays
            if let activeDays = schedule.activeDays as? [Int], activeDays.contains(weekday) {
                let timePeriods = (schedule.timePeriods as? [String]) ?? ["Morning"]
                return MedicationScheduleInfo(
                    name: medication.name ?? "Unknown medication",
                    dosage: medication.dosage ?? "1 dose",
                    timePeriods: timePeriods
                )
            }
            return nil
        }
    }
    
    private func getDateRange(for period: String) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch period.lowercased() {
        case "today", "now":
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
            
        case "tomorrow":
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            let start = calendar.startOfDay(for: tomorrow)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
            
        case "this week", "week":
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)
            
        default:
            // Default to today
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        }
    }
    
    private func groupMedicationsByTime(_ medications: [MedicationScheduleInfo]) -> [String: [MedicationScheduleInfo]] {
        var grouped: [String: [MedicationScheduleInfo]] = [:]
        
        for medication in medications {
            for period in medication.timePeriods {
                let timeKey = formatScheduleTime(period)
                if grouped[timeKey] == nil {
                    grouped[timeKey] = []
                }
                grouped[timeKey]?.append(medication)
            }
        }
        
        return grouped
    }
    
    private func formatScheduleTime(_ timePeriod: String) -> String {
        // Convert time period to readable format
        switch timePeriod.lowercased() {
        case "morning": return "8:00 AM"
        case "afternoon": return "2:00 PM"
        case "evening": return "8:00 PM"
        case "night": return "10:00 PM"
        default: return timePeriod
        }
    }
    
    private func formatScheduleResponse(_ schedule: [String: [MedicationScheduleInfo]], for period: String) -> String {
        var response = "Your medication schedule for \(period):\n\n"
        
        // Sort times
        let sortedTimes = schedule.keys.sorted { time1, time2 in
            // Simple string sort for now
            return time1 < time2
        }
        
        for time in sortedTimes {
            guard let medications = schedule[time] else { continue }
            
            response += "At \(time):\n"
            for medication in medications {
                response += "• \(medication.name) - \(medication.dosage)\n"
            }
            response += "\n"
        }
        
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

