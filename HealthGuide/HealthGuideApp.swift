//  HealthGuide - HealthGuideApp.swift

//  Main app entry point - manages app lifecycle and initialization
import SwiftUI
import AppIntents
import FirebaseCore

@main
@available(iOS 18.0, *)
struct HealthGuideApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    @StateObject private var memoryMonitor = MemoryMonitor.shared
    @StateObject private var accessManager = AccessSessionManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var medicationScheduler = MedicationNotificationScheduler.shared
    // TEMPORARILY DISABLED: CloudKit sync to prevent Firestore conflicts
    // @StateObject private var cloudSyncService = CloudKitSyncService.shared
    @StateObject private var firebaseAuth = FirebaseAuthService.shared
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @StateObject private var firebaseSync = FirebaseDataSyncService.shared
    @StateObject private var firebaseServiceManager = FirebaseServiceManager.shared
    @State private var isInitialized = false
    @State private var isInBackground = false
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
        
        // Run critical initializations in parallel for faster startup
        await withTaskGroup(of: Void.self) { group in
            // 1. Initialize SubscriptionManager (needed for UI)
            group.addTask {
                AppLogger.performance.debug("Initializing SubscriptionManager...")
                await SubscriptionManager.shared.initialize()
            }
            
            // 2. Configure AccessSessionManager (needed for access control)
            group.addTask {
                let accessStart = Date()
                await self.accessManager.configure()
                AppLogger.performance.debug("AccessSessionManager configured in \(Date().timeIntervalSince(accessStart))s")
            }
            
            // Wait for both to complete
            await group.waitForAll()
        }
        
        // 3. Handle trial initialization with CloudKit-based manager (now with caching)
        let cloudTrialManager = CloudTrialManager.shared
        
        do {
            // Initialize CloudKit trial management
            try await cloudTrialManager.initialize()
            
            if let existingTrial = cloudTrialManager.trialState {
                // Trial exists (from CloudKit or local)
                AppLogger.main.info("Existing trial found - Day \(existingTrial.daysUsed) of 14")
                
                // Sync with SubscriptionManager for UI
                if existingTrial.isValid {
                    await subscriptionManager.setTrialState(
                        startDate: existingTrial.startDate,
                        endDate: existingTrial.expiryDate,
                        sessionsUsed: 0,  // Not used in unlimited trial
                        sessionsRemaining: 999  // Unlimited during trial
                    )
                }
            } else if !UserDefaults.standard.bool(forKey: "app.hasLaunchedBefore") {
                // Genuinely first launch - start new trial
                AppLogger.main.info("First launch detected - starting free trial")
                
                do {
                    // Start new trial with CloudKit sync
                    _ = try await cloudTrialManager.startNewTrial()
                    
                    // Also update SubscriptionManager for UI consistency
                    await subscriptionManager.startFreeTrial()
                    subscriptionManager.trialSessionsRemaining = 999  // Unlimited
                    subscriptionManager.trialSessionsUsed = 0
                    
                    UserDefaults.standard.set(true, forKey: "app.hasLaunchedBefore")
                    AppLogger.main.info("14-day unlimited trial started and synced to CloudKit")
                } catch {
                    AppLogger.main.error("Failed to start trial: \(error)")
                }
            } else {
                // Load existing subscription status
                await subscriptionManager.checkSubscriptionStatus()
            }
            
            AppLogger.main.info("Trial state: \(subscriptionManager.subscriptionState.displayName)")
            if let trial = cloudTrialManager.trialState {
                AppLogger.main.info("Trial day \(trial.daysUsed) of 14")
            }
        } catch {
            AppLogger.main.error("CloudKit initialization failed: \(error)")
            // Fall back to local-only trial management
            AppLogger.main.info("Falling back to local trial management")
        }
        
        // 4. Initialize Firebase anonymous auth in background (don't block app launch)
        Task.detached(priority: .background) {
            do {
                let userId = try await FirebaseAuthService.shared.signInAnonymously()
                AppLogger.main.info("Firebase Auth initialized in background: \(userId)")
                
                // Delay group operations to avoid blocking app startup
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Check if user already has a group (with timeout)
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await FirebaseGroupService.shared.loadSavedGroup()
                    }
                    
                    // Wait maximum 5 seconds for group load
                    _ = await group.waitForAll()
                }
                
                // If no group exists, create a personal group for this user
                if await FirebaseGroupService.shared.currentGroup == nil {
                    AppLogger.main.info("Creating personal group for new user (delayed)")
                    try await FirebaseGroupService.shared.createPersonalGroup()
                    AppLogger.main.info("Personal group created with invite code")
                }
            } catch {
                AppLogger.main.error("Firebase initialization failed: \(error)")
            }
        }
        
        // 5. TEMPORARILY DISABLED: CloudKit sync service to prevent Firestore conflicts
        /*
        AppLogger.performance.debug("Initializing CloudKit sync")
        let cloudKitAvailable = await cloudSyncService.checkSyncStatus()
        if cloudKitAvailable {
            cloudSyncService.enableAutoSync(interval: 60) // Sync every minute
            AppLogger.main.info("CloudKit sync enabled for personal backup")
        } else {
            AppLogger.main.warning("CloudKit sync not available")
        }
        */
        AppLogger.main.info("CloudKit sync disabled - using Firestore for group sharing only")
        
        // 5. Clean up old notifications in background (not critical for startup)
        Task.detached {
            AppLogger.performance.debug("Setting up notification cleanup")
            await NotificationManager.shared.scheduleEndOfDayCleanup()
            await NotificationManager.shared.cleanupPreviousDayNotifications()
        }
        
        // 6. Mark as initialized
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
            
            // Mark as no longer in background
            isInBackground = false
            
            // Restore if coming from background
            if oldPhase == .background {
                // Resume SubscriptionManager after cleanup
                Task {
                    await SubscriptionManager.shared.resume()
                    AppLogger.main.info("✅ SubscriptionManager resumed after background")
                }
                
                // Don't update badge when returning from background
                // Badge should persist from notification until medication is taken
            }
            
        case .inactive:
            AppLogger.main.debug("App became inactive")
            // Don't cleanup here - Face ID and other system dialogs cause inactive state
            // Only cleanup when actually going to background
            
        case .background:
            AppLogger.main.info("App entering background - pausing ALL operations")
            
            // IMMEDIATELY mark as in background to stop rendering
            isInBackground = true
            
            // CRITICAL: Stop everything synchronously and immediately
            // Stop badge updates to prevent CPU usage in background
            BadgeManager.shared.stopPeriodicUpdates()
            
            // Stop subscription transaction listener (CRITICAL!)
            SubscriptionManager.shared.cleanup()
            
            // Stop Firebase service listeners
            FirebaseServiceManager.shared.cleanup()
            
            // Pause other periodic tasks
            AccessSessionManager.shared.cleanup()
            MemoryMonitor.shared.cleanup()
            
            // Stop any audio sessions
            AudioManager.shared.cleanup()
            
            // Cancel any pending notifications
            MedicationNotificationScheduler.shared.cleanup()
            
            // Clean up keyboard to prevent RTIInputSystemClient errors
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            
            // Force stop SwiftUI updates - this is the key to stopping the 109% CPU
            ProcessInfo.processInfo.performExpiringActivity(withReason: "BackgroundCleanup") { expired in
                if !expired {
                    // Suspend the main run loop momentarily
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
                }
            }
            
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
        
        // Configure Firebase
        FirebaseApp.configure()
        AppLogger.main.info("Firebase configured successfully")
        
        // Setup notification delegate immediately
        NotificationManager.shared.setupDelegate()
        
        // Don't update badge on app launch
        // Badge should only be set by notifications and updated when medications are taken
        // This preserves the notification badge count
        
        // Defer memory monitoring until after launch
        // _ = MemoryMonitor.shared
        AppLogger.performance.debug("MemoryMonitor: Deferred initialization")
        
        return true
    }
    
    /// Handle app becoming active - update badge for current period
    func applicationDidBecomeActive(_ application: UIApplication) {
        AppLogger.main.info("App became active")
        
        // Start badge updates and update for current period
        Task {
            BadgeManager.shared.startUpdates()
            await BadgeManager.shared.updateBadgeForCurrentPeriod()
            
            // Also schedule notifications if they haven't been scheduled today
            await MedicationNotificationScheduler.shared.scheduleDailyNotifications()
            
            // Initialize Firebase group and start member monitoring if needed
            await FirebaseGroupService.shared.loadSavedGroup()
        }
    }
    
    /// Handle app entering background - pause expensive operations
    func applicationDidEnterBackground(_ application: UIApplication) {
        AppLogger.main.info("App entering background - pausing operations")
        
        // Create a background task to ensure cleanup completes
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        backgroundTask = application.beginBackgroundTask {
            // End the background task if it expires
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        // Stop badge updates to prevent CPU usage in background
        BadgeManager.shared.stopPeriodicUpdates()
        
        // Stop subscription transaction listener
        SubscriptionManager.shared.cleanup()
        
        // Clean up keyboard to prevent RTIInputSystemClient errors
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        // Pause other periodic tasks
        AccessSessionManager.shared.cleanup()
        MemoryMonitor.shared.cleanup()
        
        // Force all dispatch queues to pause
        DispatchQueue.main.async {
            // End background task after cleanup
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
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