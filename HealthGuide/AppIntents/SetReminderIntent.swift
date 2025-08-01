//
//  SetReminderIntent.swift
//  HealthGuide
//
//  Siri intent for setting medication reminders
//

import AppIntents
import CoreData
import UserNotifications

@available(iOS 18.0, *)
struct SetReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Medication Reminder"
    static let description = IntentDescription("Set a reminder to take your medication")
    
    @Parameter(title: "Medication Name")
    var medicationName: String?
    
    @Parameter(title: "Time", default: "2pm")
    var reminderTime: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to take \(\.$medicationName) at \(\.$reminderTime)")
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Check notification permission
        let notificationCenter = UNUserNotificationCenter.current()
        let settings = await notificationCenter.notificationSettings()
        
        guard settings.authorizationStatus == .authorized else {
            return .result(
                value: "Permission needed",
                dialog: "I need permission to send notifications. Please enable notifications in Settings."
            )
        }
        
        // Get Core Data context
        let context = PersistenceController.shared.container.viewContext
        
        // Find medication
        let medication = try await IntentHelpers.findMedication(
            named: medicationName,
            in: context
        )
        
        guard let medication = medication else {
            return .result(
                value: "No medication found",
                dialog: "I couldn't find that medication. Please specify which medication to remind you about."
            )
        }
        
        // Parse reminder time
        let scheduledTime = IntentHelpers.interpretTime(reminderTime)
        
        // Extract medication info before crossing actor boundary
        let medicationId = medication.id
        let medicationName = medication.name ?? "Unknown medication"
        let medicationDosage = medication.dosage ?? "1 dose"
        
        // Create notification
        let success = await scheduleNotification(
            medicationId: medicationId,
            medicationName: medicationName,
            medicationDosage: medicationDosage,
            at: scheduledTime
        )
        
        if success {
            let medicationName = IntentHelpers.formatMedicationName(medication)
            let timeString = IntentHelpers.formatTimeRelative(scheduledTime)
            
            return .result(
                value: "Reminder set",
                dialog: "I'll remind you to take \(medicationName) \(timeString)."
            )
        } else {
            return .result(
                value: "Failed",
                dialog: "Sorry, I couldn't set that reminder. Please try again."
            )
        }
    }
    
    @MainActor
    private func scheduleNotification(
        medicationId: UUID?,
        medicationName: String,
        medicationDosage: String,
        at date: Date
    ) async -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        content.body = "Time to take \(medicationName) - \(medicationDosage)"
        content.sound = .default
        content.categoryIdentifier = "MEDICATION_REMINDER"
        content.userInfo = [
            "medicationId": medicationId?.uuidString ?? "",
            "medicationName": medicationName
        ]
        
        // Create trigger
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        
        // Create request
        let requestId = "med_reminder_\(medicationId?.uuidString ?? UUID().uuidString)_\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(
            identifier: requestId,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        do {
            try await notificationCenter.add(request)
            
            // Note: We can't update the medication here since we don't have the managed object
            // The reminder is scheduled successfully
            
            return true
        } catch {
            print("❌ Failed to schedule notification: \(error)")
            return false
        }
    }
}
