//
//  AccessSessionEntity+Extensions.swift
//  HealthGuide
//
//  Core Data extensions for daily access session tracking
//  Implements once-per-day access control for basic users
//

import Foundation
import CoreData
import UIKit
import UIKit

@available(iOS 18.0, *)
extension AccessSessionEntity {
    
    // MARK: - Initialization
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Debug: Log thread info
        #if DEBUG
        print("🧵 AccessSessionEntity.awakeFromInsert on thread: \(Thread.current)")
        print("   Is Main Thread: \(Thread.isMainThread)")
        #endif
        
        let now = Date()
        
        // Generate unique ID
        self.id = UUID()
        
        // Set user identifier (device-specific for now)
        // Core Data calls this on background thread, so we can't access UIDevice directly
        self.userId = "unknown" // Will be set later
        
        // Session timing
        self.sessionStartTime = now
        self.accessDate = now
        self.isActive = true
        
        // Subscription status (false = basic user)
        // TEMPORARY: Default to false for debugging (avoid SubscriptionManager access)
        self.accessType = false
        
        // Usage tracking
        self.featuresAccessed = "[]" // Empty JSON array
        self.actionCount = 0
        self.medicationUpdatesCount = 0
        self.documentsViewed = 0
        
        // Device metadata
        // Core Data calls this on background thread, so we can't access UIDevice directly
        self.deviceModel = "Unknown" // Will be set later
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.timeZone = TimeZone.current.identifier
        self.sessionDurationSeconds = 0
        
        // Session history
        if let lastSession = AccessSessionEntity.fetchLastSession(for: userId ?? "", context: self.managedObjectContext!) {
            self.previousSessionId = lastSession.id?.uuidString
            
            // Calculate days since first use
            if let firstSession = AccessSessionEntity.fetchFirstSession(for: userId ?? "", context: self.managedObjectContext!) {
                let days = Calendar.current.dateComponents([.day], from: firstSession.createdAt ?? now, to: now).day ?? 0
                self.daysSinceFirstUse = Int32(days)
            }
        } else {
            self.daysSinceFirstUse = 0
        }
        
        // Total session count
        let count = AccessSessionEntity.fetchSessionCount(for: userId ?? "", context: self.managedObjectContext!)
        self.totalSessionsCount = Int32(count + 1)
        
        // Timestamps
        self.createdAt = now
        self.updatedAt = now
    }
    
    // MARK: - Device Info (Must be called on Main Thread)
    
    /// Set device-specific information - MUST be called on main thread
    @MainActor
    func setDeviceInfo() {
        self.userId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        self.deviceModel = UIDevice.current.model
        
        // Also set subscription status here
        self.accessType = SubscriptionManager.shared.subscriptionState.isActive
    }
    
    // MARK: - Session Management
    
    /// End the current session
    func endSession() {
        guard isActive else { return }
        
        self.isActive = false
        self.sessionEndTime = Date()
        
        // Calculate session duration
        if let startTime = sessionStartTime {
            self.sessionDurationSeconds = Int32(Date().timeIntervalSince(startTime))
        }
        
        self.updatedAt = Date()
    }
    
    /// Track feature usage during session
    func trackFeatureUse(_ feature: String) {
        var features: [String] = []
        
        // Decode existing features
        if let jsonString = featuresAccessed,
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            features = decoded
        }
        
        // Add new feature if not already tracked
        if !features.contains(feature) {
            features.append(feature)
        }
        
        // Encode back to JSON
        if let encoded = try? JSONEncoder().encode(features),
           let jsonString = String(data: encoded, encoding: .utf8) {
            self.featuresAccessed = jsonString
        }
        
        self.actionCount += 1
        self.updatedAt = Date()
    }
    
    /// Track medication updates
    func trackMedicationUpdate() {
        self.medicationUpdatesCount += 1
        self.actionCount += 1
        self.updatedAt = Date()
        trackFeatureUse("medication_update")
    }
    
    /// Track document views (basic users can view but not upload)
    func trackDocumentView() {
        self.documentsViewed += 1
        self.actionCount += 1
        self.updatedAt = Date()
        trackFeatureUse("document_view")
    }
    
    // MARK: - Static Queries
    
    /// Check if user has accessed today (for basic users only)
    static func hasAccessedToday(userId: String, context: NSManagedObjectContext) -> Bool {
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Only check basic user sessions (accessType = false)
        request.predicate = NSPredicate(
            format: "userId == %@ AND accessDate >= %@ AND accessDate < %@ AND accessType == NO",
            userId, startOfDay as NSDate, endOfDay as NSDate
        )
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking daily access: \(error)")
            return false
        }
    }
    
    /// Get active session for user
    static func getActiveSession(for userId: String, context: NSManagedObjectContext) -> AccessSessionEntity? {
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND isActive == YES", userId)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "sessionStartTime", ascending: false)]
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching active session: \(error)")
            return nil
        }
    }
    
    /// Get today's session for user
    static func getTodaySession(for userId: String, context: NSManagedObjectContext) -> AccessSessionEntity? {
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        request.predicate = NSPredicate(
            format: "userId == %@ AND accessDate >= %@ AND accessDate < %@",
            userId, startOfDay as NSDate, endOfDay as NSDate
        )
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "sessionStartTime", ascending: false)]
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching today's session: \(error)")
            return nil
        }
    }
    
    /// Get last session for user
    static func fetchLastSession(for userId: String, context: NSManagedObjectContext) -> AccessSessionEntity? {
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        return try? context.fetch(request).first
    }
    
    /// Get first session for user
    static func fetchFirstSession(for userId: String, context: NSManagedObjectContext) -> AccessSessionEntity? {
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        
        return try? context.fetch(request).first
    }
    
    /// Get total session count for user
    static func fetchSessionCount(for userId: String, context: NSManagedObjectContext) -> Int {
        let request: NSFetchRequest<AccessSessionEntity> = AccessSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        
        return (try? context.count(for: request)) ?? 0
    }
    
    // MARK: - Analytics
    
    /// Analyze usage pattern for gaming detection
    func analyzeUsagePattern() -> UsagePattern {
        let avgActionRate = sessionDurationSeconds > 0 ? Float(actionCount) / Float(sessionDurationSeconds) : 0
        
        // Quick bulk updates (>1 action per 10 seconds)
        if avgActionRate > 0.1 && medicationUpdatesCount > 10 {
            return .suspicious
        }
        
        // Very short session (<60 seconds) with updates
        if sessionDurationSeconds < 60 && actionCount > 5 {
            return .suspicious
        }
        
        // Trying to access premium features
        if !accessType && documentsViewed > 0 {
            return .upgradeable
        }
        
        return .normal
    }
    
    /// Get time until next available access (for basic users)
    static func timeUntilNextAccess(for userId: String, context: NSManagedObjectContext) -> TimeInterval? {
        // Premium users have no wait time
        // Skip subscription check here - it's handled at the UI layer
        // This avoids cross-thread access issues
        
        // Check if accessed today
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        
        if hasAccessedToday(userId: userId, context: context) {
            return tomorrow.timeIntervalSince(Date())
        }
        
        // Haven't accessed today - available now
        return 0
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, *)
enum UsagePattern {
    case normal
    case suspicious  // Possible gaming behavior
    case upgradeable // Using/trying premium features
}