//   HealthGuide-HealthGuideShortcuts.swift
//  Main shortcuts provider that registers all app intents with Siri

import AppIntents

@available(iOS 18.0, *)
struct HealthGuideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Check Schedule
        AppShortcut(
            intent: CheckScheduleIntent(),
            phrases: [
                "Check my medications in \(.applicationName)",
                "What medications do I need to take in \(.applicationName)",
                "Check my medication schedule in \(.applicationName)",
                "What pills do I take today in \(.applicationName)",
                "Show my medication schedule in \(.applicationName)",
                "List today's medications in \(.applicationName)"
            ],
            shortTitle: "Check Schedule",
            systemImageName: "calendar.badge.clock"
        )
        
        // Check Next Dose
        AppShortcut(
            intent: CheckNextDoseIntent(),
            phrases: [
                "Check next dose in \(.applicationName)",
                "When's my next medication in \(.applicationName)",
                "Next dose time in \(.applicationName)",
                "When should I take my medicine in \(.applicationName)"
            ],
            shortTitle: "Next Dose",
            systemImageName: "clock.fill"
        )
        
        // Set Reminder
        AppShortcut(
            intent: SetReminderIntent(),
            phrases: [
                "Set medication reminder in \(.applicationName)",
                "Remind me about my medication in \(.applicationName)",
                "Set a pill reminder in \(.applicationName)"
            ],
            shortTitle: "Set Reminder",
            systemImageName: "bell.badge"
        )
        
        // Schedule Medication
        AppShortcut(
            intent: ScheduleMedicationIntent(),
            phrases: [
                "Add medication schedule in \(.applicationName)",
                "Schedule my vitamins in \(.applicationName)",
                "Set up medication routine in \(.applicationName)"
            ],
            shortTitle: "Schedule Medication",
            systemImageName: "calendar.badge.plus"
        )
    }
    
    static let shortcutTileColor: ShortcutTileColor = .blue
}
