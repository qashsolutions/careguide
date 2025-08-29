//
//  NotificationManager.swift
//  HealthGuide
//
//  Production-ready notification management system
//  Handles trial reminders, medication reminders, and subscription notifications
//

import Foundation
@preconcurrency import UserNotifications
import SwiftUI

@available(iOS 18.0, *)
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    @Published var isNotificationEnabled = false
    @Published var notificationSettings: UNNotificationSettings?
    
    // MARK: - Private Properties
    // Access notification center through computed property to avoid sendability issues
    private nonisolated var notificationCenter: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }
    private let notificationQueue = DispatchQueue(label: "com.healthguide.notifications", qos: .utility)
    
    // MARK: - Notification Identifiers
    private enum NotificationIdentifier {
        // Updated for 14-day trial
        static let earlyReminderDay10 = "trial.reminder.day10"
        static let paymentPromptDay12 = "trial.payment.day12"
        static let urgentExportDay13 = "trial.export.day13"
        static let finalWarningDay14 = "trial.final.day14"
        static let trialExpiredDay14 = "trial.expired.day14"
        static let subscriptionRenewed = "subscription.renewed"
        static let subscriptionExpiring = "subscription.expiring"
        static let medicationPrefix = "medication."
    }
    
    // MARK: - Notification Categories
    private enum NotificationCategory {
        static let trialReminder = "TRIAL_REMINDER"
        static let paymentPrompt = "PAYMENT_PROMPT"
        static let medication = "MEDICATION"
        static let subscription = "SUBSCRIPTION"
    }
    
    // MARK: - Initialization
    private override init() {
        super.init()
        // Don't set delegate in init to avoid race conditions
        // notificationCenter.delegate = self
        setupNotificationCategories()
        // Don't check status in init - let the app call it when ready
    }
    
    /// Initialize notification delegate - call this after app is ready
    nonisolated func setupDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Setup
    private func setupNotificationCategories() {
        // Trial actions
        let upgradeAction = UNNotificationAction(
            identifier: "UPGRADE",
            title: "Upgrade Now",
            options: [.foreground]
        )
        
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind Tomorrow",
            options: []
        )
        
        let trialCategory = UNNotificationCategory(
            identifier: NotificationCategory.trialReminder,
            actions: [upgradeAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )
        
        let paymentCategory = UNNotificationCategory(
            identifier: NotificationCategory.paymentPrompt,
            actions: [upgradeAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Medication actions
        let takeMedicationAction = UNNotificationAction(
            identifier: "TAKE_MEDICATION",
            title: "Mark as Taken",
            options: []
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze 10 min",
            options: []
        )
        
        let medicationCategory = UNNotificationCategory(
            identifier: NotificationCategory.medication,
            actions: [takeMedicationAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            trialCategory,
            paymentCategory,
            medicationCategory
        ])
    }
    
    // MARK: - Permission Management
    
    /// Request notification permission with proper error handling
    func requestNotificationPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task {
                do {
                    let center = UNUserNotificationCenter.current()
                    let granted = try await center.requestAuthorization(
                        options: [.alert, .badge, .sound, .providesAppNotificationSettings]
                    )
                    
                    await MainActor.run {
                        self.isNotificationEnabled = granted
                    }
                    
                    if granted {
                        print("✅ Notification permission granted")
                        // Register for remote notifications if needed
                        await MainActor.run {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    } else {
                        print("❌ Notification permission denied")
                    }
                    
                    continuation.resume(returning: granted)
                } catch {
                    print("❌ Failed to request notification permission: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    /// Check current notification status
    nonisolated func checkNotificationStatus() async {
        // Use nonisolated context to get settings
        let center = UNUserNotificationCenter.current()
        
        // Get settings without crossing actor boundary
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                Task { @MainActor in
                    // Update properties on MainActor
                    self.notificationSettings = settings
                    self.isNotificationEnabled = settings.authorizationStatus == .authorized
                    print("📱 Notification status: \(settings.authorizationStatus.rawValue)")
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - Trial Notifications
    
    /// Schedule all trial notifications when trial starts (14-day trial)
    func scheduleTrialNotifications(startDate: Date, endDate: Date) async {
        guard isNotificationEnabled else {
            print("⚠️ Notifications disabled - skipping trial notifications")
            return
        }
        
        // Cancel any existing trial notifications
        cancelTrialNotifications()
        
        // CRITICAL: Updated for 14-day trial (was incorrectly using 7-day logic)
        
        // Day 10: First gentle reminder (4 days left)
        if let day10 = Calendar.current.date(byAdding: .day, value: 10, to: startDate) {
            await scheduleEarlyTrialReminder(date: day10, daysLeft: 4)
        }
        
        // Day 12: Payment prompt with export warning (2 days left)
        if let day12 = Calendar.current.date(byAdding: .day, value: 12, to: startDate) {
            await schedulePaymentPromptReminder(date: day12)
        }
        
        // Day 13: URGENT - Export your data NOW (1 day left)
        if let day13 = Calendar.current.date(byAdding: .day, value: 13, to: startDate) {
            await scheduleUrgentExportReminder(date: day13)
        }
        
        // Day 14 morning: FINAL WARNING - Export immediately
        if let day14Morning = Calendar.current.date(byAdding: .day, value: 14, to: startDate) {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: day14Morning)
            components.hour = 9
            components.minute = 0
            if let morningDate = Calendar.current.date(from: components) {
                await scheduleFinalExportWarning(date: morningDate)
            }
        }
        
        // Day 14 EOD: Trial expired - Access blocked
        await scheduleTrialExpiryReminder(date: endDate)
    }
    
    /// Schedule early trial reminder (Day 10)
    func scheduleEarlyTrialReminder(date: Date, daysLeft: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Your Trial Has 4 Days Remaining"
        content.body = "You have 4 days left in your free trial. Subscribe now to keep unlimited access to all features."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.trialReminder
        content.userInfo = ["type": "trial_reminder", "day": 10, "daysLeft": daysLeft]
        
        _ = await scheduleNotification(
            identifier: NotificationIdentifier.earlyReminderDay10,
            content: content,
            date: date
        )
    }
    
    /// Schedule payment prompt reminder (Day 12)
    @discardableResult
    func schedulePaymentPromptReminder(date: Date) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Trial Ends in 2 Days - Action Required"
        content.body = "Your trial ends in 2 days! Subscribe now or EXPORT your data:\n• Documents: Tap (...) → Share\n• Contacts: Screenshot or write down\n• Memos: Save audio files"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.paymentPrompt
        content.userInfo = ["type": "payment_prompt", "day": 12]
        
        // Add image attachment if available
        if let imageURL = Bundle.main.url(forResource: "payment-reminder", withExtension: "png") {
            do {
                let attachment = try UNNotificationAttachment(
                    identifier: "payment-image",
                    url: imageURL,
                    options: nil
                )
                content.attachments = [attachment]
            } catch {
                print("Failed to attach image: \(error)")
            }
        }
        
        return await scheduleNotification(
            identifier: NotificationIdentifier.paymentPromptDay12,
            content: content,
            date: date
        )
    }
    
    /// Schedule URGENT export reminder (Day 13)
    func scheduleUrgentExportReminder(date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "🚨 URGENT: Trial Ends Tomorrow!"
        content.body = "EXPORT YOUR DATA NOW!\n• Documents will be inaccessible\n• Contacts will be locked\n• Memos cannot be played\nSubscribe or export everything TODAY!"
        content.sound = .defaultCritical
        content.categoryIdentifier = NotificationCategory.paymentPrompt
        content.userInfo = ["type": "urgent_export", "day": 13]
        content.interruptionLevel = .timeSensitive
        
        _ = await scheduleNotification(
            identifier: NotificationIdentifier.urgentExportDay13,
            content: content,
            date: date
        )
    }
    
    /// Schedule FINAL export warning (Day 14 morning)
    func scheduleFinalExportWarning(date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "⛔ FINAL WARNING: Trial Expires Today!"
        content.body = "You have HOURS left!\n• Export all documents NOW\n• Save contact information\n• Download memo recordings\nAccess will be BLOCKED tonight!"
        content.sound = .defaultCritical
        content.categoryIdentifier = NotificationCategory.paymentPrompt
        content.userInfo = ["type": "final_warning", "day": 14]
        content.interruptionLevel = .critical
        
        _ = await scheduleNotification(
            identifier: NotificationIdentifier.finalWarningDay14,
            content: content,
            date: date
        )
    }
    
    /// Schedule trial ending reminder - DEPRECATED (kept for backwards compatibility)
    func scheduleTrialEndingReminder(date: Date, daysLeft: Int) async {
        // This method is deprecated - we now use specific day reminders
        // Kept only for backwards compatibility
    }
    
    /// Schedule trial expiry notification (Day 14 EOD)
    func scheduleTrialExpiryReminder(date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Trial Expired - Access Blocked"
        content.body = "Your 14-day trial has ended. Subscribe now to regain access to your data and continue using HealthGuide."
        content.sound = .defaultCritical
        content.categoryIdentifier = NotificationCategory.trialReminder
        content.userInfo = ["type": "trial_expired", "day": 14]
        content.interruptionLevel = .critical
        
        await scheduleNotification(
            identifier: NotificationIdentifier.trialExpiredDay14,
            content: content,
            date: date
        )
    }
    
    // MARK: - Medication Reminders
    
    /// Schedule a medication reminder
    @discardableResult
    func scheduleMedicationReminder(
        medicationId: UUID,
        medicationName: String,
        dosage: String,
        time: Date,
        repeats: Bool = true
    ) async -> Bool {
        guard isNotificationEnabled else {
            print("⚠️ Notifications disabled - cannot schedule medication reminder")
            return false
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        content.body = "Time to take \(medicationName) - \(dosage)"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.medication
        content.userInfo = [
            "type": "medication",
            "medicationId": medicationId.uuidString,
            "medicationName": medicationName
        ]
        
        let identifier = "\(NotificationIdentifier.medicationPrefix)\(medicationId.uuidString)"
        
        if repeats {
            // Daily repeating notification
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )
            
            return await scheduleNotificationWithTrigger(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
        } else {
            // One-time notification
            return await scheduleNotification(
                identifier: identifier,
                content: content,
                date: time
            )
        }
    }
    
    /// Cancel a medication reminder
    func cancelMedicationReminder(medicationId: UUID) {
        let identifier = "\(NotificationIdentifier.medicationPrefix)\(medicationId.uuidString)"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        print("🗑️ Cancelled medication reminder: \(identifier)")
    }
    
    // MARK: - Helper Methods
    
    /// Schedule a notification at a specific date
    @discardableResult
    private func scheduleNotification(
        identifier: String,
        content: UNNotificationContent,
        date: Date
    ) async -> Bool {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        
        return await scheduleNotificationWithTrigger(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
    }
    
    /// Schedule a notification with a specific trigger - Swift 6 async/await compliant
    @discardableResult
    nonisolated private func scheduleNotificationWithTrigger(
        identifier: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger
    ) async -> Bool {
        do {
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            
            // Use modern async/await API for thread-safe notification scheduling
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Scheduled notification: \(identifier)")
            return true
        } catch {
            print("❌ Failed to schedule notification \(identifier): \(error)")
            return false
        }
    }
    
    /// Cancel all trial-related notifications
    func cancelTrialNotifications() {
        let identifiers = [
            // 14-day trial identifiers
            NotificationIdentifier.earlyReminderDay10,
            NotificationIdentifier.paymentPromptDay12,
            NotificationIdentifier.urgentExportDay13,
            NotificationIdentifier.finalWarningDay14,
            NotificationIdentifier.trialExpiredDay14
        ]
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🗑️ Cancelled all trial notifications")
    }
    
    /// Get all pending notifications
    func getPendingNotifications() async -> [String] {
        // Return only identifiers to avoid Sendable issues
        return await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                let identifiers = requests.map { $0.identifier }
                continuation.resume(returning: identifiers)
            }
        }
    }
    
    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }
    
    // MARK: - Auto-Cleanup for Old Notifications
    
    /// Schedule daily cleanup of old notifications at midnight
    func scheduleEndOfDayCleanup() async {
        // Get current date components
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        
        // Set to next midnight (00:00)
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        guard let midnight = calendar.date(from: components),
              let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) else {
            print("❌ Failed to calculate midnight for cleanup")
            return
        }
        
        // Create notification content for internal cleanup trigger
        let content = UNMutableNotificationContent()
        content.title = "" // Silent notification
        content.body = ""
        content.userInfo = ["type": "cleanup_trigger", "silent": true]
        
        // Create daily repeating trigger at midnight
        let triggerComponents = calendar.dateComponents([.hour, .minute], from: nextMidnight)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents,
            repeats: true // Daily repeat
        )
        
        // Schedule the cleanup trigger
        let request = UNNotificationRequest(
            identifier: "daily.cleanup.trigger",
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
            print("✅ Scheduled daily notification cleanup at midnight")
        } catch {
            print("❌ Failed to schedule cleanup: \(error)")
        }
        
        // Also perform immediate cleanup of old notifications
        await cleanupOldMedicationNotifications()
    }
    
    /// Clean up medication notifications older than their relevant period
    nonisolated func cleanupOldMedicationNotifications() async {
        let center = UNUserNotificationCenter.current()
        
        // Get delivered notifications
        let notifications = await center.deliveredNotifications()
        
        let calendar = Calendar.current
        let now = Date()
        var idsToRemove: [String] = []
        
        for notification in notifications {
            let userInfo = notification.request.content.userInfo
            let notificationDate = notification.date
            
            // Check if it's a medication notification
            if let period = userInfo["period"] as? String {
                var shouldRemove = false
                
                // Calculate cutoff times based on period
                switch period {
                case "morning":
                    // Remove morning notifications after 12 PM same day
                    if let cutoff = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: notificationDate),
                       now > cutoff {
                        shouldRemove = true
                    }
                case "afternoon":
                    // Remove afternoon notifications after 6 PM same day
                    if let cutoff = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: notificationDate),
                       now > cutoff {
                        shouldRemove = true
                    }
                case "evening":
                    // Remove evening notifications after midnight
                    if !calendar.isDateInToday(notificationDate) {
                        shouldRemove = true
                    }
                default:
                    // For any other notifications, remove if older than 24 hours
                    if now.timeIntervalSince(notificationDate) > 86400 {
                        shouldRemove = true
                    }
                }
                
                if shouldRemove {
                    idsToRemove.append(notification.request.identifier)
                }
            } else {
                // Non-medication notifications: remove if older than 24 hours
                if now.timeIntervalSince(notificationDate) > 86400 {
                    idsToRemove.append(notification.request.identifier)
                }
            }
        }
        
        // Remove old notifications
        if !idsToRemove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
            print("🧹 Cleaned up \(idsToRemove.count) old notifications")
            
            // Log which notifications were removed for debugging
            for id in idsToRemove {
                print("  - Removed: \(id)")
            }
        }
    }
    
    /// Clean up all notifications from previous days (called at app launch)
    nonisolated func cleanupPreviousDayNotifications() async {
        let center = UNUserNotificationCenter.current()
        
        // Get delivered notifications
        let notifications = await center.deliveredNotifications()
        
        let calendar = Calendar.current
        var idsToRemove: [String] = []
        
        for notification in notifications {
            // Remove all notifications not from today
            if !calendar.isDateInToday(notification.date) {
                idsToRemove.append(notification.request.identifier)
            }
        }
        
        // Remove old notifications
        if !idsToRemove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
            print("🧹 Cleaned up \(idsToRemove.count) notifications from previous days")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

@available(iOS 18.0, *)
extension NotificationManager: UNUserNotificationCenterDelegate {
    
    /// Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Check if this is the cleanup trigger notification
        let userInfo = notification.request.content.userInfo
        if userInfo["type"] as? String == "cleanup_trigger" {
            // Silent notification - perform cleanup but don't show
            // Call nonisolated cleanup method directly
            await cleanupOldMedicationNotifications()
            return [] // Don't show this notification
        }
        
        // Always show other notifications in foreground for important reminders
        return [.banner, .sound, .badge, .list]
    }
    
    /// Handle notification tap actions
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        // Extract values from userInfo before entering MainActor context
        let medicationId = userInfo["medicationId"] as? String
        let medicationName = userInfo["medicationName"] as? String
        let notificationType = userInfo["type"] as? String
        
        await MainActor.run {
            switch actionIdentifier {
            case "UPGRADE":
                // Post notification to show subscription view
                NotificationCenter.default.post(
                    name: Notification.Name("ShowSubscriptionView"),
                    object: nil
                )
                
            case "REMIND_LATER":
                // Schedule reminder for tomorrow
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                Task { @MainActor in
                    await NotificationManager.shared.schedulePaymentPromptReminder(date: tomorrow)
                }
                
            case "TAKE_MEDICATION":
                // Post notification to mark medication as taken
                if let medicationId = medicationId {
                    // Check if this is a dose-based notification
                    if let doseId = userInfo["doseId"] as? String,
                       let doseUUID = UUID(uuidString: doseId) {
                        // Mark the specific dose as taken
                        Task { @MainActor in
                            await MedicationNotificationScheduler.shared.markDoseAsTaken(doseUUID)
                        }
                    } else {
                        // Legacy support for older notifications
                        NotificationCenter.default.post(
                            name: Notification.Name("MarkMedicationTaken"),
                            object: nil,
                            userInfo: ["medicationId": medicationId]
                        )
                    }
                }
                
            case "SNOOZE":
                // Snooze medication reminder for 10 minutes
                if let doseId = userInfo["doseId"] as? String,
                   let doseUUID = UUID(uuidString: doseId) {
                    // Snooze the dose-based notification
                    let snoozeTime = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
                    let itemName = userInfo["itemName"] as? String ?? "Medication"
                    let itemDosage = userInfo["itemDosage"] as? String ?? "Snoozed dose"
                    let itemType = userInfo["itemType"] as? String ?? "medication"
                    
                    Task { @MainActor in
                        await MedicationNotificationScheduler.shared.scheduleNotification(
                            id: "\(doseId)_snooze_\(Date().timeIntervalSince1970)",
                            title: "Snoozed Reminder",
                            body: "Time to take \(itemName) - \(itemDosage)",
                            time: snoozeTime,
                            itemId: doseUUID,
                            itemName: itemName,
                            itemDosage: itemDosage,
                            itemType: itemType,
                            isMainNotification: true
                        )
                    }
                } else if let medicationId = medicationId,
                   let medicationName = medicationName {
                    // Legacy support
                    let snoozeTime = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
                    Task { @MainActor in
                        await NotificationManager.shared.scheduleMedicationReminder(
                            medicationId: UUID(uuidString: medicationId) ?? UUID(),
                            medicationName: medicationName,
                            dosage: "Snoozed dose",
                            time: snoozeTime,
                            repeats: false
                        )
                    }
                }
                
            case UNNotificationDefaultActionIdentifier:
                // Handle notification tap based on type
                if let type = notificationType {
                    switch type {
                    case "payment_prompt", "trial_ending", "trial_expired":
                        NotificationCenter.default.post(
                            name: Notification.Name("ShowSubscriptionView"),
                            object: nil
                        )
                    case "medication":
                        NotificationCenter.default.post(
                            name: Notification.Name("ShowMedicationView"),
                            object: nil
                        )
                    default:
                        break
                    }
                }
                
            default:
                break
            }
        }
    }
    
    /// Handle notification settings changes
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        // Don't create tasks in nonisolated context
        // The system will handle opening settings
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSubscriptionView = Notification.Name("ShowSubscriptionView")
    static let showMedicationView = Notification.Name("ShowMedicationView")
    static let markMedicationTaken = Notification.Name("MarkMedicationTaken")
    
    // Selective data change notifications for debounced updates
    static let groupDataDidChange = Notification.Name("groupDataDidChange")
    static let medicationDataDidChange = Notification.Name("medicationDataDidChange")
    static let supplementDataDidChange = Notification.Name("supplementDataDidChange")
    static let dietDataDidChange = Notification.Name("dietDataDidChange")
    static let contactDataDidChange = Notification.Name("contactDataDidChange")
    static let documentDataDidChange = Notification.Name("documentDataDidChange")
}