//
//  AccessSessionManager.swift
//  HealthGuide
//
//  Manages daily access sessions for basic users
//  Enforces once-per-day access limitation
//

import Foundation
import CoreData
import UIKit

@available(iOS 18.0, *)
@MainActor
final class AccessSessionManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = AccessSessionManager()
    
    // MARK: - Published Properties
    @Published var canAccess: Bool = true
    @Published var currentSession: AccessSessionEntity?
    @Published var timeUntilNextAccess: TimeInterval = 0
    @Published var isCheckingAccess: Bool = false
    
    // MARK: - Private Properties
    private let persistenceController = PersistenceController.shared
    private let deviceCheckManager = DeviceCheckManager.shared
    private let cloudTrialManager = CloudTrialManager.shared
    private var backgroundTime: Date?
    private let gracePeriod: TimeInterval = 300 // 5 minutes
    private weak var accessCheckTimer: Timer?
    private var isConfigured = false
    private var cachedUserId: String?
    
    // User identifier - now uses DeviceCheck for persistent tracking
    var userId: String {
        get async {
            if let cached = cachedUserId {
                return cached
            }
            let deviceId = await deviceCheckManager.getDeviceIdentifier()
            cachedUserId = deviceId
            return deviceId
        }
    }
    
    // MARK: - Initialization
    private init() {
        // Minimal init - no dependencies or heavy operations
        #if DEBUG
        print("🧵 AccessSessionManager.init on thread: \(Thread.current)")
        print("   Is Main Thread: \(Thread.isMainThread)")
        #endif
    }
    
    // MARK: - Configuration
    
    /// Configure the manager after app initialization
    func configure() async {
        guard !isConfigured else { return }
        isConfigured = true
        
        // CloudKit trial initialization happens in HealthGuideApp
        // Just setup notifications and check access here
        
        setupNotifications()
        await checkAccess(subscriptionState: nil)
    }
    
    // MARK: - Access Control
    
    /// Main access check with subscription state parameter
    func checkAccess(subscriptionState: SubscriptionManager.SubscriptionState?) async {
        print("🔍 Checking access...")
        isCheckingAccess = true
        
        // SUPERUSER CHECK - Your device always has access
        let deviceId = await userId
        
        let superuserDevices = [
            "C9629DA1-0AAF-4964-83C3-62BC97CF9928", // Your iPhone - Superuser access
        ]
        
        if superuserDevices.contains(deviceId) {
            canAccess = true
            isCheckingAccess = false
            print("👑 SUPERUSER - Unlimited access granted!")
            return
        }
        
        // If subscription state provided, use it; otherwise fetch current state
        let currentSubscriptionState: SubscriptionManager.SubscriptionState
        if let state = subscriptionState {
            currentSubscriptionState = state
        } else {
            // Only access SubscriptionManager after configuration
            currentSubscriptionState = isConfigured ? SubscriptionManager.shared.subscriptionState : .none
        }
        
        // Trial users have unlimited access for 14 days
        if currentSubscriptionState.isInTrial {
            // Check trial state from CloudTrialManager (CloudKit + local)
            if let trialState = cloudTrialManager.trialState {
                if trialState.isValid {
                    canAccess = true
                    isCheckingAccess = false
                    print("🎉 Trial user - Day \(trialState.daysUsed) of 14 (unlimited access)")
                    return
                } else if trialState.requiresPayment {
                    // Trial expired - hard paywall
                    canAccess = false
                    isCheckingAccess = false
                    print("❌ Trial expired - Payment required (Day 14+)")
                    return
                }
            } else {
                // No trial state found - shouldn't happen but handle gracefully
                canAccess = false
                isCheckingAccess = false
                print("⚠️ No trial state found in CloudKit")
                return
            }
        }
        
        // Premium users always have access
        if currentSubscriptionState.isActive {
            canAccess = true
            isCheckingAccess = false
            print("✅ Premium user - unlimited access")
            return
        }
        
        print("🔄 Checking Core Data...")
        // Use main context for now to avoid background task issues
        let context = persistenceController.container.viewContext
        
        let userIdentifier = await userId
        print("👤 User ID: \(userIdentifier)")
        
        // Check for active session (app was backgrounded)
        print("🔍 Checking for active session...")
        if let activeSession = AccessSessionEntity.getActiveSession(for: userIdentifier, context: context) {
            currentSession = activeSession
            canAccess = true
            isCheckingAccess = false
            print("📱 Resuming active session: \(activeSession.id?.uuidString ?? "")")
            return
        }
        
        // Check if already accessed today using DeviceCheck
        print("🔍 Checking if accessed today...")
        let deviceAccessUsed = await deviceCheckManager.isDailyAccessUsed()
        if deviceAccessUsed || AccessSessionEntity.hasAccessedToday(userId: userIdentifier, context: context) {
            canAccess = false
            updateTimeUntilNextAccess()
            isCheckingAccess = false
            print("🚫 Daily access already used")
            return
        }
        
        // Can access - will start session when user enters app
        canAccess = true
        isCheckingAccess = false
        print("✅ Access available for today")
    }
    
    /// Start a new daily session
    func startDailySession() async {
        #if DEBUG
        print("🧵 startDailySession called")
        #endif
        
        guard canAccess else { return }
        
        // Don't start multiple sessions
        if currentSession?.isActive == true { return }
        
        // Record trial access (no deduction for unlimited 14-day trial)
        let subscriptionManager = SubscriptionManager.shared
        if subscriptionManager.subscriptionState.isInTrial {
            // Just log the access for analytics
            if let trialState = cloudTrialManager.trialState {
                print("🎫 Trial access recorded - Day \(trialState.daysUsed) of 14")
                
                // Check if should show payment modal
                if trialState.shouldShowPaymentModal {
                    print("💳 User should see payment modal")
                    // UI will handle showing the modal
                }
            }
        }
        
        let context = persistenceController.container.viewContext
        
        // Create new session
        let session = AccessSessionEntity(context: context)
        
        // Set session info
        session.id = UUID()
        session.userId = await userId
        session.createdAt = Date()
        session.updatedAt = Date()
        session.sessionStartTime = Date()
        session.accessDate = Date()
        session.isActive = true
        session.deviceModel = UIDevice.current.model
        session.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        session.timeZone = TimeZone.current.identifier
        
        // Save
        do {
            print("💾 About to save Core Data context...")
            try context.save()
            print("✅ Core Data save successful")
            print("🎯 Started new session: \(session.id?.uuidString ?? "")")
            
            currentSession = session
            trackSessionStart()
            startSessionMonitoring()
            
            // Mark daily access as used in DeviceCheck
            await deviceCheckManager.markDailyAccessUsed()
        } catch {
            print("❌ Failed to start session: \(error)")
        }
    }
    
    /// End current session
    func endCurrentSession() async {
        guard let session = currentSession, session.isActive else { return }
        
        session.endSession()
        
        // Save changes
        do {
            try persistenceController.container.viewContext.save()
            print("🏁 Ended session: \(session.id?.uuidString ?? "")")
            
            stopSessionMonitoring()
            currentSession = nil
            await checkAccess(subscriptionState: nil)
        } catch {
            print("❌ Failed to end session: \(error)")
        }
    }
    
    // MARK: - Background Handling
    
    @objc private func appDidEnterBackground() {
        backgroundTime = Date()
        print("📱 App backgrounded at: \(backgroundTime!)")
    }
    
    @objc private func appWillEnterForeground() {
        guard let bgTime = backgroundTime else {
            Task {
                await checkAccess(subscriptionState: nil)
            }
            return
        }
        
        let timeInBackground = Date().timeIntervalSince(bgTime)
        print("📱 App foregrounded after: \(timeInBackground)s")
        
        if timeInBackground < gracePeriod {
            // Continue session
            print("✅ Continuing session (within grace period)")
        } else {
            // End session and check access
            Task {
                await endCurrentSession()
            }
        }
        
        backgroundTime = nil
    }
    
    // MARK: - Feature Tracking
    
    /// Track feature usage
    func trackFeatureUse(_ feature: String) {
        guard let session = currentSession else { return }
        
        session.trackFeatureUse(feature)
        saveContext()
    }
    
    /// Track medication update
    func trackMedicationUpdate() {
        guard let session = currentSession else { return }
        
        session.trackMedicationUpdate()
        saveContext()
    }
    
    /// Track document view
    func trackDocumentView() {
        guard let session = currentSession else { return }
        
        session.trackDocumentView()
        saveContext()
    }
    
    private func saveContext() {
        do {
            try persistenceController.container.viewContext.save()
        } catch {
            print("❌ Failed to save context: \(error)")
        }
    }
    
    // MARK: - Time Management
    
    private func updateTimeUntilNextAccess() {
        Task { @MainActor in
            let context = persistenceController.container.viewContext
            let userIdentifier = await userId
            
            if let time = AccessSessionEntity.timeUntilNextAccess(for: userIdentifier, context: context) {
            timeUntilNextAccess = time
            
            // DISABLED - Timer causing constant UI refreshes and high energy usage
            // Only update when user actively checks
            /*
            accessCheckTimer?.invalidate()
            accessCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in
                    self.updateTimeUntilNextAccess()
                    
                    // Check if it's a new day
                    if self.timeUntilNextAccess <= 0 {
                        await self.checkAccess(subscriptionState: nil)
                        self.accessCheckTimer?.invalidate()
                    }
                }
            }
            */
            }
        }
    }
    
    /// Format time for display
    func formattedTimeUntilNextAccess() -> String {
        let hours = Int(timeUntilNextAccess) / 3600
        let minutes = Int(timeUntilNextAccess) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Session Monitoring
    
    private func startSessionMonitoring() {
        // Monitor for inactivity, crashes, etc.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // Monitor memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    private func stopSessionMonitoring() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func appWillTerminate() {
        Task {
            await endCurrentSession()
        }
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received - cleaning up...")
        // Clear any caches or non-essential data
    }
    
    // MARK: - Analytics
    
    /// Get session analytics
    func getSessionAnalytics() async -> SessionAnalytics {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        let userIdentifier = await userId
        request.predicate = NSPredicate(format: "userId == %@", userIdentifier)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 30 // Last 30 sessions
        
        do {
            let sessions = try context.fetch(request)
            
            let totalSessions = sessions.count
            let avgDuration = sessions.compactMap { $0.sessionDurationSeconds }.reduce(0, +) / max(1, Int32(totalSessions))
            let avgActions = sessions.compactMap { $0.actionCount }.reduce(0, +) / max(1, Int32(totalSessions))
            
            let upgradeableSessions = sessions.filter { session in
                session.analyzeUsagePattern() == .upgradeable
            }.count
            
            return SessionAnalytics(
                totalSessions: totalSessions,
                averageSessionDuration: Int(avgDuration),
                averageActionsPerSession: Int(avgActions),
                upgradeOpportunities: upgradeableSessions
            )
        } catch {
            print("❌ Failed to fetch analytics: \(error)")
            return SessionAnalytics()
        }
    }
    
    // MARK: - Helpers
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func trackSessionStart() {
        // Future: Send to analytics service
        print("📊 Session started")
    }
    
    // MARK: - Memory Management
    
    /// Cleanup resources
    func cleanup() {
        accessCheckTimer?.invalidate()
        accessCheckTimer = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        // Can't access MainActor-isolated properties from deinit
        // Cleanup should be called explicitly when needed
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, *)
struct SessionAnalytics {
    let totalSessions: Int
    let averageSessionDuration: Int // seconds
    let averageActionsPerSession: Int
    let upgradeOpportunities: Int
    
    init(totalSessions: Int = 0, 
         averageSessionDuration: Int = 0, 
         averageActionsPerSession: Int = 0, 
         upgradeOpportunities: Int = 0) {
        self.totalSessions = totalSessions
        self.averageSessionDuration = averageSessionDuration
        self.averageActionsPerSession = averageActionsPerSession
        self.upgradeOpportunities = upgradeOpportunities
    }
}