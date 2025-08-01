//
//  IntentHelpers.swift
//  HealthGuide
//
//  Shared helpers for App Intents - Swift 6 compliant
//

import Foundation
import CoreData
import AppIntents

@available(iOS 18.0, *)
enum IntentHelpers {
    
    // MARK: - Time Interpretation
    static func interpretTime(_ input: String) -> Date {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        switch input.lowercased() {
        case "morning": return today.addingTimeInterval(8 * 3600)
        case "afternoon": return today.addingTimeInterval(14 * 3600)
        case "evening", "night": return today.addingTimeInterval(20 * 3600)
        case "now": return now
        default:
            // Try to parse time like "2pm", "14:00"
            return parseTimeString(input) ?? now
        }
    }
    
    private static func parseTimeString(_ time: String) -> Date? {
        let formatters = [
            DateFormatter.timeFormatter(format: "h:mma"),
            DateFormatter.timeFormatter(format: "ha"),
            DateFormatter.timeFormatter(format: "HH:mm"),
            DateFormatter.timeFormatter(format: "H:mm")
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: time) {
                return Calendar.current.date(
                    bySettingHour: Calendar.current.component(.hour, from: date),
                    minute: Calendar.current.component(.minute, from: date),
                    second: 0,
                    of: Date()
                )
            }
        }
        return nil
    }
    
    // MARK: - Medication Search
    static func findMedication(
        named name: String?,
        in context: NSManagedObjectContext
    ) async throws -> MedicationEntity? {
        let request = MedicationEntity.fetchRequest()
        
        if let name = name, !name.isEmpty {
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", name)
        } else {
            request.sortDescriptors = [NSSortDescriptor(keyPath: \MedicationEntity.updatedAt, ascending: false)]
            request.fetchLimit = 1
        }
        
        return try context.fetch(request).first
    }
    
    // MARK: - Response Formatting
    static func formatMedicationName(_ medication: MedicationEntity) -> String {
        medication.name ?? "your medication"
    }
    
    static func formatDosage(_ medication: MedicationEntity) -> String {
        medication.dosage ?? "1 dose"
    }
    
    static func formatTimeRelative(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "at \(formatter.string(from: date))"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static func timeFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale.current
        return formatter
    }
}