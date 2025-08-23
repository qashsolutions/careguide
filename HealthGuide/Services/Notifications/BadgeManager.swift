//
//  BadgeManager.swift
//  HealthGuide
//
//  Centralized badge management for time-based medication counts
//  Swift 6 compliant with proper actor isolation
//

import Foundation
import UserNotifications
import SwiftUI

@available(iOS 18.0, *)
@MainActor
final class BadgeManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = BadgeManager()
    
    // MARK: - Published Properties
    @Published var currentBadgeCount: Int = 0
    
    // MARK: - Private Properties
    private var updateTask: Task<Void, Never>?
    private let coreDataManager = CoreDataManager.shared
    
    // MARK: - Initialization
    private init() {
        // Don't start periodic updates immediately - wait for first use
        // This prevents unnecessary CPU usage if badge manager is never needed
    }
    
    // MARK: - Public Methods
    
    /// Start badge manager updates (call when app becomes active)
    func startUpdates() {
        // Only start if not already running
        if updateTask == nil {
            startPeriodicUpdates()
        }
    }
    
    /// Update badge count for current time period only
    func updateBadgeForCurrentPeriod() async {
        // Check if task is cancelled before doing expensive work
        guard updateTask?.isCancelled != true else {
            print("📛 Badge update skipped - task cancelled")
            return
        }
        
        do {
            // Get current time period
            let currentPeriod = HealthDataProcessor.getCurrentTimePeriod()
            
            // Fetch all doses for today
            let allDoses = try await coreDataManager.fetchDosesForDate(Date())
            
            // Filter for current period only
            let currentPeriodDoses = allDoses.filter { dose in
                // Match period string to current period
                dose.period.lowercased() == currentPeriod.rawValue.lowercased()
            }
            
            // Count unmarked items in current period
            let unmarkedCount = currentPeriodDoses.filter { !$0.isTaken }.count
            
            // Update badge with the unmarked count
            await updateBadge(unmarkedCount)
            print("📛 Badge updated for \(currentPeriod.rawValue): \(unmarkedCount) items")
        } catch {
            print("❌ Failed to update badge: \(error)")
            // Clear badge on error
            await updateBadge(0)
        }
    }
    
    /// Clear all badges (use with caution - only when all medications are taken)
    func clearBadge() async {
        await updateBadge(0)
        print("📛 Badge cleared")
    }
    
    /// Update badge after marking medication as taken
    /// This recalculates the badge based on remaining untaken medications
    func updateAfterMedicationTaken() async {
        // Always recalculate based on current period's untaken medications
        await updateBadgeForCurrentPeriod()
    }
    
    /// Force refresh badge count
    func refreshBadge() async {
        await updateBadgeForCurrentPeriod()
    }
    
    /// Stop periodic updates (call on app termination)
    func stopPeriodicUpdates() {
        if let task = updateTask {
            task.cancel()
            updateTask = nil
            print("📛 Badge periodic updates stopped and task cancelled")
        }
    }
    
    // MARK: - Private Methods
    
    /// Update the actual badge count
    @MainActor
    private func updateBadge(_ count: Int) async {
        currentBadgeCount = count
        
        // Update notification center badge using async API
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            print("❌ Failed to set badge: \(error)")
        }
    }
    
    /// Start periodic updates to check for time period changes
    private func startPeriodicUpdates() {
        // Cancel existing task
        updateTask?.cancel()
        
        // Create a new task for periodic updates with proper cancellation
        updateTask = Task { [weak self] in
            // Update immediately first
            await self?.updateBadgeForCurrentPeriod()
            
            // Then check every 15 minutes with proper cancellation checking
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 900_000_000_000) // 15 minutes in nanoseconds
                    
                    // Check again after sleep
                    guard !Task.isCancelled else {
                        print("📛 Badge update task cancelled after sleep")
                        break
                    }
                    
                    await self?.updateBadgeForCurrentPeriod()
                } catch {
                    // Task was cancelled during sleep, exit gracefully
                    print("📛 Badge update task cancelled: \(error)")
                    break
                }
            }
            
            print("📛 Badge update task exited cleanly")
        }
    }
    
    /// Calculate which time period we're in
    private func determineNextPeriodChange() -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        
        // Find next period transition time based on updated windows
        // Breakfast: 6-11 AM, Lunch: 12-3 PM, Dinner: 5-8 PM
        let transitions = [6, 11, 12, 15, 17, 20] // Start and end of each window
        
        for transitionHour in transitions {
            if hour < transitionHour {
                return calendar.date(bySettingHour: transitionHour, minute: 0, second: 0, of: now)
            }
        }
        
        // Next transition is tomorrow morning at 6 AM
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            return calendar.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow)
        }
        
        return nil
    }
    
    deinit {
        updateTask?.cancel()
    }
}

// MARK: - Convenience Methods for Non-MainActor Contexts
@available(iOS 18.0, *)
extension BadgeManager {
    
    /// Thread-safe badge update from any context
    nonisolated func updateBadgeFromBackground() {
        Task { @MainActor in
            await updateBadgeForCurrentPeriod()
        }
    }
    
    /// Thread-safe badge update after medication taken
    nonisolated func updateAfterMedicationTakenFromBackground() {
        Task { @MainActor in
            await updateAfterMedicationTaken()
        }
    }
    
    /// Thread-safe badge clear from any context  
    nonisolated func clearBadgeFromBackground() {
        Task { @MainActor in
            await clearBadge()
        }
    }
}