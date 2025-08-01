//  HealthGuide - HealthGuideApp.swift
//  Created by Ramana Chinthapenta on 7/25/25.
//  Main app entry point - manages app lifecycle and initialization
import SwiftUI
import AppIntents

@main
@available(iOS 18.0, *)
struct HealthGuideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    let persistenceController = PersistenceController.shared
    
    init() {
        print("🚀 HealthGuideApp: Launching...")
        print("📱 iOS Version: \(UIDevice.current.systemVersion)")
        print("💾 Core Data: Initialized")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(biometricAuth)
                .onAppear {
                    print("✅ HealthGuideApp: Main window appeared")
                    // Register App Shortcuts
                    HealthGuideShortcuts.updateAppShortcutParameters()
                }
        }
    }
}

// MARK: - App Delegate
@available(iOS 18.0, *)
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Register for push notifications if needed
        // UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        //     if granted {
        //         DispatchQueue.main.async {
        //             application.registerForRemoteNotifications()
        //         }
        //     }
        // }
        return true
    }
    
    /// Handle push notification registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("📱 Push Notification Token: \(token)")
        
        // Store token for future server integration
        UserDefaults.standard.set(token, forKey: "PushNotificationToken")
    }
    
    /// Handle push notification registration failure
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for push notifications: \(error.localizedDescription)")
    }
    
    /// Handle incoming push notifications
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📬 Received push notification: \(userInfo)")
        
        // Handle the notification based on its content
        if let aps = userInfo["aps"] as? [String: Any] {
            // Process notification data
            print("📋 Notification content: \(aps)")
        }
        
        completionHandler(.newData)
    }
}
