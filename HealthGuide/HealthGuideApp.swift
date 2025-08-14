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
    @Environment(\.scenePhase) var scenePhase
    
    let persistenceController = PersistenceController.shared
    
    init() {
        AppLogger.main.info("HealthGuide launching on iOS \(UIDevice.current.systemVersion)")
        AppLogger.main.debug("Main Thread: \(Thread.isMainThread), Thread: \(Thread.current.description)")
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
                        AppLogger.main.debug("Main window appeared")
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        handleScenePhaseChange(from: oldPhase, to: newPhase)
                    }
            }
        }
    }
    
    private func initializeManagers() async {
        let signpostID = AppLogger.signpost.makeSignpostID()
        let signpostState = AppLogger.signpost.beginInterval("AppInitialization", id: signpostID)
        let startTime = Date()
        
        // 1. Skip SubscriptionManager init - let it initialize lazily when needed
        AppLogger.performance.debug("SubscriptionManager init deferred for faster launch")
        
        // 2. Configure AccessSessionManager
        let accessStart = Date()
        await accessManager.configure()
        AppLogger.performance.debug("AccessSessionManager configured in \(Date().timeIntervalSince(accessStart))s")
        
        // 3. Auto-start trial on first launch
        if !UserDefaults.standard.bool(forKey: "app.hasLaunchedBefore") {
            AppLogger.main.info("First launch detected - starting free trial")
            await subscriptionManager.startFreeTrial()
            UserDefaults.standard.set(true, forKey: "app.hasLaunchedBefore")
            AppLogger.main.info("Trial auto-started with 30 sessions")
            AppLogger.main.info("Trial state: \(subscriptionManager.subscriptionState.displayName)")
            AppLogger.main.info("Sessions remaining: \(subscriptionManager.trialSessionsRemaining)")
        } else {
            // Load existing trial session data if in trial
            await subscriptionManager.checkSubscriptionStatus()
            AppLogger.main.info("Subscription state: \(subscriptionManager.subscriptionState.displayName)")
            AppLogger.main.info("Sessions remaining: \(subscriptionManager.trialSessionsRemaining)")
        }
        
        // 4. Clean up old notifications and schedule daily cleanup
        AppLogger.performance.debug("Setting up notification cleanup")
        await NotificationManager.shared.cleanupPreviousDayNotifications()
        await NotificationManager.shared.scheduleEndOfDayCleanup()
        
        // 5. Mark as initialized
        await MainActor.run {
            let totalTime = Date().timeIntervalSince(startTime)
            AppLogger.performance.info("App initialization completed in \(totalTime)s")
            if totalTime > 2.0 {
                AppLogger.performance.warning("Initialization took longer than 2 seconds: \(totalTime)s")
            }
            isInitialized = true
        }
        
        AppLogger.signpost.endInterval("AppInitialization", signpostState)
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        AppLogger.main.debug("Scene phase: \(String(describing: oldPhase)) → \(String(describing: newPhase))")
        
        switch newPhase {
        case .active:
            AppLogger.main.info("App became active")
            // Restart subscription transaction listener
            Task {
                await SubscriptionManager.shared.initialize()
            }
            
            // Start periodic badge updates
            Task { @MainActor in
                BadgeManager.shared.startUpdates()
                await BadgeManager.shared.updateBadgeForCurrentPeriod()
            }
            
            // Clean up old notifications when app becomes active
            Task {
                await NotificationManager.shared.cleanupOldMedicationNotifications()
            }
            
        case .inactive:
            AppLogger.main.debug("App became inactive")
            // App is transitioning, don't do heavy cleanup yet
            
        case .background:
            AppLogger.main.info("App entering background - pausing operations")
            
            // Stop badge updates to prevent CPU usage in background
            BadgeManager.shared.stopPeriodicUpdates()
            
            // Stop subscription transaction listener (CRITICAL!)
            SubscriptionManager.shared.cleanup()
            
            // Clean up keyboard to prevent RTIInputSystemClient errors
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            
            // Pause other periodic tasks
            AccessSessionManager.shared.cleanup()
            MemoryMonitor.shared.cleanup()
            
            AppLogger.main.debug("Background cleanup complete")
            
        @unknown default:
            AppLogger.main.warning("Unknown scene phase encountered")
        }
    }
}

// MARK: - App Delegate
@available(iOS 18.0, *)
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        #if DEBUG
        AppLogger.main.debug("AppDelegate: didFinishLaunching")
        #endif
        
        // Setup notification delegate immediately
        NotificationManager.shared.setupDelegate()
        
        // Clear badge on app launch (Swift 6 compliant)
        DispatchQueue.main.async {
            Task {
                await BadgeManager.shared.clearBadge()
            }
        }
        
        // Defer memory monitoring until after launch
        // _ = MemoryMonitor.shared
        AppLogger.performance.debug("MemoryMonitor: Deferred initialization")
        
        return true
    }
    
    /// Handle app becoming active - update badge for current period
    func applicationDidBecomeActive(_ application: UIApplication) {
        AppLogger.main.info("App became active")
        
        // Restart subscription transaction listener
        Task {
            await SubscriptionManager.shared.initialize()
        }
        
        DispatchQueue.main.async {
            Task {
                // Start periodic badge updates when app becomes active
                BadgeManager.shared.startUpdates()
                await BadgeManager.shared.updateBadgeForCurrentPeriod()
            }
        }
    }
    
    /// Handle app entering background - pause expensive operations
    func applicationDidEnterBackground(_ application: UIApplication) {
        AppLogger.main.info("App entering background - pausing operations")
        
        // Stop badge updates to prevent CPU usage in background
        BadgeManager.shared.stopPeriodicUpdates()
        
        // Stop subscription transaction listener
        SubscriptionManager.shared.cleanup()
        
        // Clean up keyboard to prevent RTIInputSystemClient errors
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Pause other periodic tasks
        AccessSessionManager.shared.cleanup()
        MemoryMonitor.shared.cleanup()
        
        AppLogger.main.debug("Background cleanup complete")
    }
    
    /// Handle app termination - clean up resources
    func applicationWillTerminate(_ application: UIApplication) {
        AppLogger.main.info("App terminating - starting cleanup")
        
        // Cancel badge update task to prevent CPU spike
        BadgeManager.shared.stopPeriodicUpdates()
        
        // Stop subscription transaction listener (CRITICAL - this was the CPU spike cause!)
        SubscriptionManager.shared.cleanup()
        
        // Clean up other managers with timers/tasks
        // Clean up access session manager timer
        AccessSessionManager.shared.cleanup()
        
        // Clean up memory monitor timer
        MemoryMonitor.shared.cleanup()
        
        // Clean up notification scheduler if needed
        MedicationNotificationScheduler.shared.cleanup()
        
        // Clean up audio manager resources
        AudioManager.shared.cleanup()
        
        AppLogger.main.info("App termination cleanup complete")
    }
    
    /// Handle push notification registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        AppLogger.notification.logPrivate("Push token received", privateData: token)
        
        // Store token for future server integration
        UserDefaults.standard.set(token, forKey: "PushNotificationToken")
    }
    
    /// Handle push notification registration failure
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.notification.error("Failed to register for push notifications: \(error.localizedDescription)")
    }
    
    /// Handle incoming push notifications
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        AppLogger.notification.debug("Received push notification")
        
        // Handle the notification based on its content
        if userInfo["aps"] != nil {
            // Process notification data when needed
            AppLogger.notification.debug("Notification content received")
        }
        
        completionHandler(.newData)
    }
    
    /// Handle memory warnings
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        AppLogger.performance.warning("Memory warning received")
        Task { @MainActor in
            MemoryMonitor.shared.performEmergencyCleanup()
        }
    }
}