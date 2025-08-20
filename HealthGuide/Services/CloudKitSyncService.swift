//
//  CloudKitSyncService.swift
//  HealthGuide
//
//  Real-time CloudKit sync service for group data
//

import Foundation
import CloudKit
import CoreData
import Combine

@available(iOS 18.0, *)
@MainActor
final class CloudKitSyncService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = CloudKitSyncService()
    
    // MARK: - Properties
    private let container: CKContainer
    // TEMPORARILY DISABLED: CloudKit container to prevent Firestore conflicts
    // private let persistentContainer: NSPersistentCloudKitContainer
    private let persistentContainer: NSPersistentContainer
    private var subscriptions = Set<AnyCancellable>()
    private var syncTimer: Timer?
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    
    // MARK: - Initialization
    private init() {
        self.container = CKContainer(identifier: "iCloud.com.qashsolutions.HealthGuide")
        self.persistentContainer = PersistenceController.shared.container
        
        // TEMPORARILY DISABLED: CloudKit listeners to prevent Firestore conflicts
        // setupCloudKitListeners()
        print("☁️ CloudKitSyncService initialized (CloudKit disabled)")
    }
    
    // MARK: - Setup Listeners
    private func setupCloudKitListeners() {
        // TEMPORARILY DISABLED: CloudKit listeners to prevent Firestore conflicts
        /*
        // Listen for remote change notifications
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.handleRemoteChanges()
                }
            }
            .store(in: &subscriptions)
        
        // Listen for Core Data saves to trigger sync
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .debounce(for: .seconds(2), scheduler: RunLoop.main) // Debounce to avoid too many syncs
            .sink { [weak self] notification in
                Task {
                    await self?.syncIfNeeded(from: notification)
                }
            }
            .store(in: &subscriptions)
        */
    }
    
    // MARK: - Handle Remote Changes
    private func handleRemoteChanges() async {
        print("🔄 Received remote CloudKit changes")
        
        isSyncing = true
        defer { 
            isSyncing = false
            lastSyncDate = Date()
        }
        
        // Refresh the context to get latest data
        persistentContainer.viewContext.refreshAllObjects()
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .groupDataDidChange,
            object: nil
        )
    }
    
    // MARK: - Sync if Needed
    private func syncIfNeeded(from notification: Notification) async {
        // Check if the save includes group-related entities
        guard let userInfo = notification.userInfo,
              let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>,
              let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> else {
            return
        }
        
        let allObjects = insertedObjects.union(updatedObjects)
        let hasGroupData = allObjects.contains { object in
            object is CareGroupEntity ||
            object is GroupMemberEntity ||
            object is MedicationEntity ||
            object is SupplementEntity ||
            object is DietEntity ||
            object is ContactEntity ||
            object is DocumentEntity ||
            object is CareMemoEntity
        }
        
        if hasGroupData {
            print("🔄 Group data changed, triggering sync")
            await performSync()
        }
    }
    
    // MARK: - Manual Sync
    func performSync() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        defer { 
            isSyncing = false
            lastSyncDate = Date()
        }
        
        print("🔄 Performing CloudKit sync")
        
        // NSPersistentCloudKitContainer handles the actual sync
        // We just need to ensure the context is saved
        do {
            if persistentContainer.viewContext.hasChanges {
                try persistentContainer.viewContext.save()
            }
            print("✅ CloudKit sync completed")
        } catch {
            print("❌ CloudKit sync failed: \(error)")
            syncError = error.localizedDescription
        }
    }
    
    // MARK: - Check Sync Status
    func checkSyncStatus() async -> Bool {
        // TEMPORARILY DISABLED: CloudKit sync to prevent Firestore conflicts
        print("⚠️ CloudKit sync disabled - using Firestore for group sharing")
        return false
        /*
        do {
            // Check if we can reach CloudKit
            let accountStatus = try await container.accountStatus()
            
            switch accountStatus {
            case .available:
                print("✅ CloudKit account available")
                return true
            case .noAccount:
                print("⚠️ No CloudKit account")
                syncError = "Please sign in to iCloud in Settings"
                return false
            case .restricted:
                print("⚠️ CloudKit restricted")
                syncError = "CloudKit access is restricted"
                return false
            case .couldNotDetermine:
                print("⚠️ Could not determine CloudKit status")
                syncError = "Could not verify iCloud status"
                return false
            case .temporarilyUnavailable:
                print("⚠️ CloudKit temporarily unavailable")
                syncError = "iCloud is temporarily unavailable"
                return false
            @unknown default:
                return false
            }
        } catch {
            print("❌ Failed to check CloudKit status: \(error)")
            syncError = error.localizedDescription
            return false
        }
        */
    }
    
    // MARK: - Enable Auto Sync
    func enableAutoSync(interval: TimeInterval = 30) {
        // TEMPORARILY DISABLED: CloudKit sync to prevent Firestore conflicts
        print("⚠️ CloudKit auto-sync disabled - using Firestore for group sharing")
        /*
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task {
                await self.performSync()
            }
        }
        print("✅ Auto-sync enabled with interval: \(interval)s")
        */
    }
    
    // MARK: - Disable Auto Sync
    func disableAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        print("⏸ Auto-sync disabled")
    }
}

// MARK: - Notification Names
// Using existing .groupDataDidChange from NotificationManager.swift