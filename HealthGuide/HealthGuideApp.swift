//  HealthGuide - HealthGuideApp.swift

//  Main app entry point - manages app lifecycle and initialization
import SwiftUI
import AppIntents

@main
@available(iOS 18.0, *)
struct HealthGuideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    @StateObject private var memoryMonitor = MemoryMonitor.shared
    @StateObject private var accessManager = AccessSessionManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isInitialized = false
    
    let persistenceController = PersistenceController.shared
    
    init() {
        #if DEBUG
        print("🚀 HealthGuideApp: Launching...")
        print("📱 iOS Version: \(UIDevice.current.systemVersion)")
        print("🧵 Main Thread: \(Thread.isMainThread)")
        print("🧵 Thread: \(Thread.current)")
        print("💾 Core Data: Initialized")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if !isInitialized {
                // Show loading while managers initialize
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                    .task {
                        await initializeManagers()
                    }
            } else {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(biometricAuth)
                    .environmentObject(memoryMonitor)
                    .environmentObject(accessManager)
                    .environmentObject(subscriptionManager)
                    .onAppear {
                        #if DEBUG
                        print("✅ HealthGuideApp: Main window appeared")
                        #endif
                    }
            }
        }
    }
    
    private func initializeManagers() async {
        // 1. Initialize SubscriptionManager with timeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.subscriptionManager.initialize()
            }
            
            // Add timeout
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 second timeout
            }
            
            // Wait for first to complete
            await group.next()
            group.cancelAll()
        }
        
        // 2. Configure AccessSessionManager
        await accessManager.configure()
        
        // 3. Setup NotificationManager (skip if causing issues)
        #if DEBUG
        print("🔔 Checking notification status...")
        #endif
        // Simplified - just check without waiting
        Task {
            await NotificationManager.shared.checkNotificationStatus()
        }
        #if DEBUG
        print("✅ Notification check started")
        #endif
        
        // 4. Mark as initialized immediately
        await MainActor.run {
            #if DEBUG
            print("🎯 Marking app as initialized...")
            #endif
            isInitialized = true
            #if DEBUG
            print("✅ App initialization complete - loading UI")
            #endif
        }
    }
}

// MARK: - App Delegate
@available(iOS 18.0, *)
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
        print("📲 AppDelegate: didFinishLaunching")
        #endif
        
        // Setup notification delegate immediately
        NotificationManager.shared.setupDelegate()
        
        // Start memory monitoring
        _ = MemoryMonitor.shared
        
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
    
    /// Handle memory warnings
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("⚠️ Application received memory warning")
        Task { @MainActor in
            MemoryMonitor.shared.performEmergencyCleanup()
        }
    }
}