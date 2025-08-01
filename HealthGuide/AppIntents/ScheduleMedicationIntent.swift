//
//  ScheduleMedicationIntent.swift
//  HealthGuide
//
//  Siri intent for scheduling recurring medications
//

import AppIntents
import CoreData

@available(iOS 18.0, *)
struct ScheduleMedicationIntent: AppIntent {
    static let title: LocalizedStringResource = "Schedule Medication"
    static let description = IntentDescription("Schedule a medication for regular intervals")
    
    @Parameter(title: "Medication Name")
    var medicationName: String
    
    @Parameter(title: "Frequency", default: "daily")
    var frequency: String
    
    @Parameter(title: "Time", default: "morning")
    var scheduleTime: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Schedule \(\.$medicationName) \(\.$frequency) at \(\.$scheduleTime)")
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext
        
        // Check if medication exists or create new
        let medication = try await findOrCreateMedication(
            named: medicationName,
            in: context
        )
        
        // Parse schedule parameters
        let scheduleInfo = parseScheduleParameters(
            frequency: frequency,
            time: scheduleTime
        )
        
        // Create schedule
        let schedule = ScheduleEntity(context: context)
        schedule.id = UUID()
        schedule.customTimes = [scheduleInfo.time] as NSArray
        schedule.frequency = String(scheduleInfo.frequency)
        schedule.activeDays = scheduleInfo.days.components(separatedBy: ",").compactMap { Int($0) } as NSArray
        schedule.startDate = Date()
        schedule.endDate = nil // No end date means ongoing
        schedule.medication = medication
        
        // Save
        do {
            try context.save()
            
            let timeString = IntentHelpers.formatTimeRelative(scheduleInfo.time)
            let frequencyString = formatFrequency(scheduleInfo.frequency)
            
            return .result(
                value: "Scheduled",
                dialog: "I've scheduled \(medicationName) \(frequencyString) \(timeString)."
            )
        } catch {
            return .result(
                value: "Failed",
                dialog: "Sorry, I couldn't schedule that medication. Please try again."
            )
        }
    }
    
    private func findOrCreateMedication(
        named name: String,
        in context: NSManagedObjectContext
    ) async throws -> MedicationEntity {
        // Try to find existing
        if let existing = try await IntentHelpers.findMedication(
            named: name,
            in: context
        ) {
            return existing
        }
        
        // Create new medication
        let medication = MedicationEntity(context: context)
        medication.id = UUID()
        medication.name = name
        medication.category = "medication"
        medication.createdAt = Date()
        
        return medication
    }
    
    private func parseScheduleParameters(
        frequency: String,
        time: String
    ) -> (time: Date, frequency: Int16, days: String) {
        // Parse time
        let scheduledTime = IntentHelpers.interpretTime(time)
        
        // Parse frequency
        let (frequencyValue, daysString) = parseFrequency(frequency)
        
        return (scheduledTime, frequencyValue, daysString)
    }
    
    private func parseFrequency(_ input: String) -> (Int16, String) {
        switch input.lowercased() {
        case "daily", "every day":
            return (1, "1,2,3,4,5,6,7") // All days
            
        case "twice daily", "twice a day":
            return (2, "1,2,3,4,5,6,7")
            
        case "weekly", "once a week":
            return (7, "1") // Monday only
            
        case "weekdays":
            return (1, "2,3,4,5,6") // Mon-Fri
            
        case "weekends":
            return (1, "1,7") // Sat-Sun
            
        default:
            return (1, "1,2,3,4,5,6,7") // Default to daily
        }
    }
    
    private func formatFrequency(_ frequency: Int16) -> String {
        switch frequency {
        case 1: return "daily"
        case 2: return "twice daily"
        case 7: return "weekly"
        default: return "every \(frequency) days"
        }
    }
}
