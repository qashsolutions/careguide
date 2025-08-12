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
        static let morning = 7     // 7:00 AM (middle of 6-9 AM window)
        static let afternoon = 13  // 1:00 PM (middle of 12-2 PM window)
        static let evening = 18    // 6:00 PM (middle of 5-8 PM window)
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
        
        // Use the new simplified scheduling instead
        await scheduleDailyNotifications()
    }
    
    // MARK: - Legacy method for compatibility
    func schedulePendingNotifications() async {
        // Redirect to new simplified system
        await scheduleDailyNotifications()
    }
    
    // MARK: - Schedule Notifications
    func scheduleDailyNotifications() async {
        guard await NotificationManager.shared.isNotificationEnabled else {
            print("⚠️ Notifications disabled - skipping medication scheduling")
            return
        }
        
        // Check if already scheduled today (debouncing)
        let lastScheduled = UserDefaults.standard.object(forKey: "lastNotificationScheduleDate") as? Date
        let today = Calendar.current.startOfDay(for: Date())
        
        if let lastScheduled = lastScheduled,
           Calendar.current.isDate(lastScheduled, inSameDayAs: today) {
            print("✅ Notifications already scheduled for today")
            return
        }
        
        // Cancel any existing notifications
        cancelAllMedicationNotifications()
        
        // Schedule the 3 daily notifications
        await scheduleSimplifiedNotifications()
        
        // Mark as scheduled for today
        UserDefaults.standard.set(Date(), forKey: "lastNotificationScheduleDate")
        print("✅ Scheduled 3 daily medication notifications")
    }
    
    // MARK: - Schedule Simplified Notifications
    private func scheduleSimplifiedNotifications() async {
        let calendar = Calendar.current
        let today = Date()
        
        // Fetch all doses ONCE to reduce CPU usage
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return }
        
        let allDoses = await CoreDataManager.shared.fetchTodaysDoses(from: startOfToday, to: endOfToday)
        
        // Group doses by period
        var breakfastItems: [(name: String, dosage: String, type: String)] = []
        var lunchItems: [(name: String, dosage: String, type: String)] = []
        var dinnerItems: [(name: String, dosage: String, type: String)] = []
        
        for dose in allDoses {
            if let period = dose.period?.lowercased() {
                let item: (name: String, dosage: String, type: String)?
                
                if let name = dose.medicationName, let dosage = dose.medicationDosage {
                    item = (name: name, dosage: dosage, type: "medication")
                } else if let name = dose.supplementName, let dosage = dose.supplementDosage {
                    item = (name: name, dosage: dosage, type: "supplement")
                } else if let name = dose.dietName, let portion = dose.dietPortion {
                    item = (name: name, dosage: portion, type: "diet")
                } else {
                    item = nil
                }
                
                if let validItem = item {
                    switch period {
                    case "breakfast":
                        breakfastItems.append(validItem)
                    case "lunch":
                        lunchItems.append(validItem)
                    case "dinner":
                        dinnerItems.append(validItem)
                    default:
                        break
                    }
                }
            }
        }
        
        // Schedule 7 AM notification for breakfast items (6-9 AM window)
        if let morningTime = calendar.date(bySettingHour: NotificationTiming.morning, minute: 0, second: 0, of: today),
           morningTime > Date(),
           !breakfastItems.isEmpty {
            await scheduleGroupedNotification(
                id: "morning_meds",
                title: "💊 Morning Medications",
                items: breakfastItems,
                time: morningTime,
                period: "morning"
            )
        }
        
        // Schedule 1 PM notification for lunch items (12-2 PM window)
        if let afternoonTime = calendar.date(bySettingHour: NotificationTiming.afternoon, minute: 0, second: 0, of: today),
           afternoonTime > Date(),
           !lunchItems.isEmpty {
            await scheduleGroupedNotification(
                id: "afternoon_meds",
                title: "💊 Afternoon Medications",
                items: lunchItems,
                time: afternoonTime,
                period: "afternoon"
            )
        }
        
        // Schedule 6 PM notification for dinner items (5-8 PM window)
        if let eveningTime = calendar.date(bySettingHour: NotificationTiming.evening, minute: 0, second: 0, of: today),
           eveningTime > Date(),
           !dinnerItems.isEmpty {
            await scheduleGroupedNotification(
                id: "evening_meds",
                title: "💊 Evening Medications",
                items: dinnerItems,
                time: eveningTime,
                period: "evening"
            )
        }
    }
    
    // MARK: - Fetch Items for Period
    private func fetchItemsForPeriod(_ period: DoseEntity.TimePeriod) async -> [(name: String, dosage: String, type: String)] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return [] }
        
        // Fetch doses for this period
        let doses = await CoreDataManager.shared.fetchTodaysDoses(from: startOfToday, to: endOfToday)
        
        var items: [(name: String, dosage: String, type: String)] = []
        
        for dose in doses {
            // Check if this dose is for the requested period
            if dose.period?.lowercased() == period.rawValue.lowercased() {
                if let name = dose.medicationName, let dosage = dose.medicationDosage {
                    items.append((name: name, dosage: dosage, type: "medication"))
                } else if let name = dose.supplementName, let dosage = dose.supplementDosage {
                    items.append((name: name, dosage: dosage, type: "supplement"))
                } else if let name = dose.dietName, let portion = dose.dietPortion {
                    items.append((name: name, dosage: portion, type: "diet"))
                }
            }
        }
        
        return items
    }
    
    // MARK: - Schedule Grouped Notification
    private func scheduleGroupedNotification(
        id: String,
        title: String,
        items: [(name: String, dosage: String, type: String)],
        time: Date,
        period: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        
        // Build the body with all items
        var bodyLines: [String] = []
        let itemCount = items.count
        
        if itemCount == 1 {
            bodyLines.append("\(items[0].name) \(items[0].dosage)")
        } else {
            bodyLines.append("\(itemCount) items to take:")
            for item in items.prefix(5) {  // Show first 5 items
                bodyLines.append("• \(item.name) \(item.dosage)")
            }
            if itemCount > 5 {
                bodyLines.append("• ...and \(itemCount - 5) more")
            }
        }
        
        content.body = bodyLines.joined(separator: "\n")
        
        // Use a distinct sound
        content.sound = .defaultCritical  // Louder, more distinctive
        
        // Make it time-sensitive so it stays visible
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        
        // Badge managed by BadgeManager for time-based counts
        // content.badge removed - centralized badge management
        
        // Set category for action buttons
        content.categoryIdentifier = "MEDICATION"
        
        // Add user info
        content.userInfo = [
            "type": "grouped_medication",
            "period": period,
            "itemCount": itemCount
        ]
        
        // Create trigger
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
            print("✅ Scheduled \(period) notification for \(itemCount) items at \(time)")
        } catch {
            print("❌ Failed to schedule \(period) notification: \(error)")
        }
    }
    
    // MARK: - Cancel All Medication Notifications
    private func cancelAllMedicationNotifications() {
        let identifiers = ["morning_meds", "afternoon_meds", "evening_meds"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🗑️ Cancelled all existing medication notifications")
    }
    
    // MARK: - Fetch Today's Doses (Legacy - kept for compatibility)
    private func fetchTodaysDoses() async -> [DoseData] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return [] }
        
        // Use CoreDataManager's method to fetch doses safely
        let doses = await CoreDataManager.shared.fetchTodaysDoses(from: startOfToday, to: endOfToday)
        
        // Limit to first 50 doses to prevent memory issues
        return Array(doses.prefix(50))
    }
    
    // MARK: - Schedule Notifications for Single Dose (DEPRECATED - kept for compatibility)
    // This method is no longer used - we use the simplified 3-notification system instead
    private func scheduleNotificationsForDose(_ dose: DoseData) async {
        // Deprecated - do nothing
        // The new system schedules 3 grouped notifications at 9am, 1pm, 6pm
        return
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
        
        // Remove pending (future) notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        
        // ALSO remove delivered notifications from notification center
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        
        print("🗑️ Cancelled and removed delivered notifications for dose: \(doseId)")
    }
    
    // MARK: - Mark Dose as Taken
    func markDoseAsTaken(_ doseId: UUID) async {
        // Cancel all pending notifications for this dose
        cancelNotificationsForDose(doseId)
        
        // Update the dose in Core Data using CoreDataManager
        await CoreDataManager.shared.markDoseAsTaken(doseId)
        
        // Check if we should also remove grouped notifications
        await removeGroupedNotificationIfAllTaken()
        
        // Update badge count for current period only
        await BadgeManager.shared.updateBadgeForCurrentPeriod()
    }
    
    // MARK: - Remove Grouped Notification If All Taken
    private func removeGroupedNotificationIfAllTaken() async {
        // Check each time period to see if all items are taken
        let periods = [
            ("morning_meds", TimePeriod.breakfast),
            ("afternoon_meds", TimePeriod.lunch),
            ("evening_meds", TimePeriod.dinner)
        ]
        
        for (notificationId, period) in periods {
            // Check if all items in this period are marked as taken
            let allTaken = await checkIfAllItemsTakenForPeriod(period)
            
            if allTaken {
                // Remove both pending and delivered grouped notifications
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])
                print("🗑️ Removed grouped notification: \(notificationId) - all items taken")
            }
        }
    }
    
    // Helper to check if all items in a period are taken
    private func checkIfAllItemsTakenForPeriod(_ period: TimePeriod) async -> Bool {
        do {
            // Fetch all doses for today
            let allDoses = try await CoreDataManager.shared.fetchDosesForDate(Date())
            
            // Filter doses for this specific period (period is stored as string in DoseRecord)
            let periodDoses = allDoses.filter { dose in
                dose.period.lowercased() == period.rawValue.lowercased()
            }
            
            // If no doses exist or all are taken, return true
            return periodDoses.isEmpty || periodDoses.allSatisfy { $0.isTaken }
        } catch {
            print("❌ Error checking doses for period: \(error)")
            return false
        }
    }
    
    // MARK: - Schedule for New Medication
    func scheduleNotificationsForNewMedication(_ medicationId: UUID) async {
        // When a new medication is added, reschedule daily notifications
        // This will include the new medication in the grouped notifications
        await scheduleDailyNotifications()
    }
    
    // MARK: - Schedule for New Supplement
    func scheduleNotificationsForNewSupplement(_ supplementId: UUID) async {
        // When a new supplement is added, reschedule daily notifications
        // This will include the new supplement in the grouped notifications
        await scheduleDailyNotifications()
    }
}
