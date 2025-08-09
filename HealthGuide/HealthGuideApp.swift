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
    @StateObject private var medicationScheduler = MedicationNotificationScheduler.shared
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
                    .environmentObject(medicationScheduler)
                    .onAppear {
                        #if DEBUG
                        print("✅ HealthGuideApp: Main window appeared")
                        #endif
                    }
            }
        }
    }
    
    private func initializeManagers() async {
        let startTime = Date()
        print("⏱️ [PERF] App initialization started at \(startTime)")
        
        // 1. Skip SubscriptionManager init - let it initialize lazily when needed
        let subStart = Date()
        print("⏱️ [PERF] SubscriptionManager init SKIPPED for faster launch")
        // Task {
        //     await self.subscriptionManager.initialize()
        // }
        print("⏱️ [PERF] SubscriptionManager deferred: \(Date().timeIntervalSince(subStart))s")
        
        // 2. Configure AccessSessionManager
        let accessStart = Date()
        print("⏱️ [PERF] AccessSessionManager config starting...")
        await accessManager.configure()
        print("⏱️ [PERF] AccessSessionManager took: \(Date().timeIntervalSince(accessStart))s")
        
        // 3. Skip NotificationManager check - defer until user needs notifications
        let notifStart = Date()
        print("⏱️ [PERF] NotificationManager check SKIPPED for faster launch")
        // Will check when user actually accesses notification features
        // Task {
        //     await NotificationManager.shared.checkNotificationStatus()
        // }
        print("⏱️ [PERF] NotificationManager deferred: \(Date().timeIntervalSince(notifStart))s")
        
        // 4. Initialize MedicationNotificationScheduler
        // Disabled automatic listening to prevent CPU issues
        // _ = medicationScheduler
        #if DEBUG
        print("💊 Medication notification scheduler ready (manual mode)")
        #endif
        
        // 5. Mark as initialized immediately
        await MainActor.run {
            let totalTime = Date().timeIntervalSince(startTime)
            print("⏱️ [PERF] TOTAL initialization time: \(totalTime)s")
            if totalTime > 2.0 {
                print("⚠️ [PERF] WARNING: Initialization took longer than 2 seconds!")
            }
            isInitialized = true
            print("✅ App initialization complete - loading UI")
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
        
        // Defer memory monitoring until after launch
        // _ = MemoryMonitor.shared
        print("📊 MemoryMonitor: Deferred initialization")
        
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