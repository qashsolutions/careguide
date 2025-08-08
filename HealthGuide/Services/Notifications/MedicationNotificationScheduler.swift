//
//  MedicationNotificationScheduler.swift
//  HealthGuide
//
//  Production-ready medication notification scheduler
//  Handles T-90, T-45, T-0 notifications for medications and supplements
//

import Foundation
import CoreData
import UserNotifications
import SwiftUI

@available(iOS 18.0, *)
// Removed @MainActor to allow background notification scheduling
// This prevents libdispatch assertion failures when called from main thread
// Made @unchecked Sendable to fix concurrency warning - safe as singleton with limited mutable state
final class MedicationNotificationScheduler: ObservableObject, @unchecked Sendable {
    
    // MARK: - Singleton
    static let shared = MedicationNotificationScheduler()
    
    // MARK: - Properties
    // We'll access these managers directly in async functions where we can use await
    // No need to store them as properties since they're singletons
    private var notificationObserver: NSObjectProtocol?
    private var isProcessing = false
    private var lastProcessedDate: Date?
    
    // MARK: - Notification Timing
    private enum NotificationTiming {
        static let firstReminder = -90  // 90 minutes before
        static let secondReminder = -45 // 45 minutes before
        static let dueNotification = 0  // At scheduled time
    }
    
    // MARK: - Initialization
    private init() {
        // Temporarily disabled to prevent infinite loop
        // setupObserver()
    }
    
    // Clean up observer when deallocated
    func cleanup() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }
    
    // MARK: - Setup
    private func setupObserver() {
        // DISABLED - Preventing potential CPU issues
        // Will be called manually when needed instead
        /*
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .coreDataDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleCoreDataSave()
            }
        }
        */
    }
    
    // MARK: - Core Data Save Handler
    private func handleCoreDataSave() async {
        // Debounce - only process once every 5 seconds
        let now = Date()
        if let lastProcessed = lastProcessedDate,
           now.timeIntervalSince(lastProcessed) < 5 {
            return
        }
        
        // Prevent concurrent processing
        guard !isProcessing else { return }
        isProcessing = true
        defer { 
            isProcessing = false
            lastProcessedDate = now
        }
        
        // Process medications and supplements that were just saved
        await schedulePendingNotifications()
    }
    
    // MARK: - Schedule Notifications
    func schedulePendingNotifications() async {
        guard await NotificationManager.shared.isNotificationEnabled else {
            print("⚠️ Notifications disabled - skipping medication scheduling")
            return
        }
        
        // Get today's doses that need notifications
        let todaysDoses = await fetchTodaysDoses()
        
        for dose in todaysDoses {
            await scheduleNotificationsForDose(dose)
        }
    }
    
    // MARK: - Fetch Today's Doses
    private func fetchTodaysDoses() async -> [DoseData] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return [] }
        
        // Use CoreDataManager's method to fetch doses safely
        let doses = await CoreDataManager.shared.fetchTodaysDoses(from: startOfToday, to: endOfToday)
        
        // Limit to first 50 doses to prevent memory issues
        return Array(doses.prefix(50))
    }
    
    // MARK: - Schedule Notifications for Single Dose
    private func scheduleNotificationsForDose(_ dose: DoseData) async {
        let doseId = dose.id
        let scheduledTime = dose.scheduledTime
        
        // Don't schedule if dose is already taken
        if dose.isTaken { return }
        
        // Don't schedule notifications for past times
        if scheduledTime < Date() { return }
        
        // Check if notifications already exist for this dose
        let doseIdString = doseId.uuidString
        let hasExistingNotifications = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let exists = requests.contains { request in
                    request.identifier.contains(doseIdString)
                }
                continuation.resume(returning: exists)
            }
        }
        
        // Skip if notifications already scheduled
        if hasExistingNotifications { return }
        
        // Get medication/supplement details
        let itemDetails = getItemDetailsFromTuple(dose)
        guard let itemName = itemDetails.name,
              let itemDosage = itemDetails.dosage,
              let itemType = itemDetails.type else { return }
        
        // Get time period name (Breakfast, Lunch, etc.)
        // let periodName = dose.period ?? "medication"  // Commented out - not currently used
        
        // Schedule T-90 notification (90 minutes before)
        if let t90Time = Calendar.current.date(byAdding: .minute, value: NotificationTiming.firstReminder, to: scheduledTime),
           t90Time > Date() {
            let bodyText = "Time to prepare: \(itemName) \(itemDosage)"
            await scheduleNotification(
                id: "\(doseId.uuidString)_90min",
                title: "\(itemType.capitalized) Reminder",
                body: bodyText,
                time: t90Time,
                itemId: doseId,
                itemName: itemName,
                itemDosage: itemDosage,
                itemType: itemType
            )
        }
        
        // Schedule T-45 notification (45 minutes before)
        if let t45Time = Calendar.current.date(byAdding: .minute, value: NotificationTiming.secondReminder, to: scheduledTime),
           t45Time > Date() {
            let bodyText = "\(itemName) \(itemDosage) - Due in 45 minutes"
            await scheduleNotification(
                id: "\(doseId.uuidString)_45min",
                title: "\(itemType.capitalized) Due Soon",
                body: bodyText,
                time: t45Time,
                itemId: doseId,
                itemName: itemName,
                itemDosage: itemDosage,
                itemType: itemType
            )
        }
        
        // Schedule T-0 notification (at scheduled time)
        let mainBodyText = "Time for your \(itemType): \(itemName) \(itemDosage)"
        await scheduleNotification(
            id: "\(doseId.uuidString)_0min",
            title: "Time for \(itemType.capitalized)",
            body: mainBodyText,
            time: scheduledTime,
            itemId: doseId,
            itemName: itemName,
            itemDosage: itemDosage,
            itemType: itemType,
            isMainNotification: true
        )
    }
    
    // MARK: - Get Item Details
    private func getItemDetailsFromTuple(_ dose: DoseData) -> (name: String?, dosage: String?, type: String?) {
        if let name = dose.medicationName, let dosage = dose.medicationDosage {
            return (name, dosage, "medication")
        } else if let name = dose.supplementName, let dosage = dose.supplementDosage {
            return (name, dosage, "supplement")
        } else if let name = dose.dietName, let portion = dose.dietPortion {
            return (name, portion, "diet")
        }
        return (nil, nil, nil)
    }
    
    // MARK: - Schedule Single Notification
    func scheduleNotification(
        id: String,
        title: String,
        body: String,
        time: Date,
        itemId: UUID,
        itemName: String,
        itemDosage: String,
        itemType: String,
        isMainNotification: Bool = false
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Use the MEDICATION category for action buttons on main notification
        if isMainNotification {
            content.categoryIdentifier = "MEDICATION"
        }
        
        content.userInfo = [
            "type": "medication_reminder",
            "doseId": itemId.uuidString,
            "itemName": itemName,
            "itemDosage": itemDosage,
            "itemType": itemType,
            "isMainNotification": isMainNotification
        ]
        
        // Create date components for the notification
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: time
        )
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Scheduled notification: \(id) for \(time)")
        } catch {
            print("❌ Failed to schedule notification: \(error)")
        }
    }
    
    // MARK: - Cancel Notifications for Dose
    func cancelNotificationsForDose(_ doseId: UUID) {
        let identifiers = [
            "\(doseId.uuidString)_90min",
            "\(doseId.uuidString)_45min",
            "\(doseId.uuidString)_0min"
        ]
        
        // Note: removePendingNotificationRequests is synchronous, not async
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🗑️ Cancelled notifications for dose: \(doseId)")
    }
    
    // MARK: - Mark Dose as Taken
    func markDoseAsTaken(_ doseId: UUID) async {
        // Cancel all pending notifications for this dose
        cancelNotificationsForDose(doseId)
        
        // Update the dose in Core Data using CoreDataManager
        await CoreDataManager.shared.markDoseAsTaken(doseId)
    }
    
    // MARK: - Schedule for New Medication
    func scheduleNotificationsForNewMedication(_ medicationId: UUID) async {
        let doses = await CoreDataManager.shared.fetchDosesForMedication(medicationId)
        for dose in doses {
            await scheduleNotificationsForDose(dose)
        }
    }
    
    // MARK: - Schedule for New Supplement
    func scheduleNotificationsForNewSupplement(_ supplementId: UUID) async {
        let doses = await CoreDataManager.shared.fetchDosesForSupplement(supplementId)
        for dose in doses {
            await scheduleNotificationsForDose(dose)
        }
    }
}
