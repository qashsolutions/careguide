//
//  CheckNextDoseIntent.swift
//  HealthGuide
//
//  Siri intent for checking next medication dose time
//  Responds to queries like "When's my next dose?"
//

import AppIntents
import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct CheckNextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Next Dose"
    static let description = IntentDescription("Check when your next medication dose is scheduled")
    
    // Enhanced for better Siri recognition
    static let searchKeywords: [String] = ["medication", "dose", "medicine", "pill", "next", "when"]
    static let openAppWhenRun = false
    
    // Parameters
    @Parameter(title: "Medication Name")
    var medicationName: String?
    
    @Parameter(title: "Time Frame", default: "today")
    var timeFrame: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Check next dose \(\.$medicationName)")
    }
    
    // Suggested phrases for Siri
    static var suggestedInvocationPhrase: String {
        "What's my next dose"
    }
    
    // Main execution
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext
        
        // Donate activity for Siri predictions
        donateActivity()
        
        // Find next scheduled dose
        let nextDose = try await findNextDose(medicationName: medicationName, context: context)
        
        guard let dose = nextDose,
              let medication = dose.medication,
              let scheduledTime = dose.scheduledTime else {
            return .result(
                value: "No scheduled doses",
                dialog: "You don't have any medications scheduled for today. Check with your healthcare provider if you have questions."
            )
        }
        
        let medicationName = IntentHelpers.formatMedicationName(medication)
        let timeString = IntentHelpers.formatTimeRelative(scheduledTime)
        let dosage = IntentHelpers.formatDosage(medication)
        
        // Check if it's overdue
        if scheduledTime < Date() && !dose.isTaken {
            return .result(
                value: "Overdue: \(medicationName)",
                dialog: "Your \(medicationName) (\(dosage)) was due \(timeString). Please take it as soon as possible."
            )
        }
        
        return .result(
            value: "\(medicationName) \(timeString)",
            dialog: "Your next dose is \(medicationName) (\(dosage)) scheduled \(timeString)."
        )
    }
    
    // Helper to find next dose
    private func findNextDose(
        medicationName: String?,
        context: NSManagedObjectContext
    ) async throws -> DoseEntity? {
        let request = DoseEntity.fetchRequest()
        
        // Base predicate: not taken and scheduled for today or future
        var predicates = [NSPredicate]()
        predicates.append(NSPredicate(format: "isTaken == NO"))
        predicates.append(NSPredicate(format: "scheduledTime != nil"))
        
        // Filter by medication name if provided
        if let name = medicationName, !name.isEmpty {
            let medicationPredicate = NSPredicate(
                format: "medication.name CONTAINS[cd] %@", name
            )
            predicates.append(medicationPredicate)
        }
        
        // Combine predicates
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        // Sort by scheduled time
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \DoseEntity.scheduledTime, ascending: true)
        ]
        
        // Limit to next dose
        request.fetchLimit = 1
        
        return try context.fetch(request).first
    }
    
    // Donate activity for better Siri predictions
    private func donateActivity() {
        let activity = NSUserActivity(activityType: "com.healthguide.checkNextDose")
        activity.title = "Check Next Dose"
        activity.userInfo = ["medicationName": medicationName ?? ""]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = "checkNextDose"
        activity.becomeCurrent()
    }
}