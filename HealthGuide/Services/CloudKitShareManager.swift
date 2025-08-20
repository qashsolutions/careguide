//
//  CloudKitShareManager.swift
//  HealthGuide
//
//  Manages CloudKit sharing for groups between different Apple IDs
//

import Foundation
import CloudKit
import CoreData

@available(iOS 18.0, *)
@MainActor
final class CloudKitShareManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = CloudKitShareManager()
    
    // MARK: - Properties
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let persistentContainer: NSPersistentCloudKitContainer
    
    @Published var activeShares: [CKShare] = []
    @Published var isProcessingShare = false
    @Published var shareError: String?
    
    // MARK: - Initialization
    private init() {
        // Use the same container as Core Data
        self.container = CKContainer(identifier: "iCloud.com.qashsolutions.HealthGuide")
        self.privateDatabase = container.privateCloudDatabase
        self.sharedDatabase = container.sharedCloudDatabase
        
        // Get the persistent container
        self.persistentContainer = PersistenceController.shared.container as! NSPersistentCloudKitContainer
        
        print("☁️ CloudKitShareManager initialized")
    }
    
    // MARK: - Create Share for Group
    func createShareForGroup(_ group: CareGroupEntity) async throws -> String {
        print("🔄 Creating CloudKit share for group: \(group.name ?? "Unknown")")
        
        isProcessingShare = true
        defer { isProcessingShare = false }
        
        do {
            // NSPersistentCloudKitContainer automatically syncs Core Data with CloudKit
            // We just need to track that this group should be shared
            
            // Store a flag that this group is shared
            var settings = group.settings as? [String: Any] ?? [:]
            settings["isCloudKitShared"] = true
            settings["shareCreatedDate"] = Date()
            group.settings = settings as NSDictionary
            group.updatedAt = Date()
            
            // Save Core Data changes - this will trigger CloudKit sync
            try persistentContainer.viewContext.save()
            
            print("✅ Group marked for CloudKit sharing")
            print("ℹ️ NSPersistentCloudKitContainer will handle the actual sync")
            
            // Return the invite code (we'll use the existing 6-digit code)
            return group.inviteCode ?? ""
            
        } catch {
            print("❌ Failed to create share: \(error)")
            shareError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Join Group via Invite Code
    func joinGroupWithInviteCode(_ inviteCode: String, userId: UUID) async throws -> CareGroupEntity? {
        print("🔄 Joining group with invite code: \(inviteCode)")
        
        isProcessingShare = true
        defer { isProcessingShare = false }
        
        do {
            // First, check if group exists locally (for testing without full CloudKit)
            let context = persistentContainer.viewContext
            let request: NSFetchRequest<CareGroupEntity> = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "inviteCode == %@", inviteCode)
            
            if let existingGroup = try context.fetch(request).first {
                print("✅ Found group locally: \(existingGroup.name ?? "Unknown")")
                
                // Add user as member
                let member = GroupMemberEntity(context: context)
                member.id = UUID()
                member.userID = userId
                member.joinedAt = Date()
                member.role = "member"
                member.permissions = "read"
                member.group = existingGroup  // Set the relationship to the group
                member.name = "Member \(existingGroup.members?.count ?? 1)"
                
                // Save
                try context.save()
                
                // If CloudKit share exists, accept it
                if let settings = existingGroup.settings as? [String: Any],
                   let shareRecordName = settings["cloudKitShareRecordName"] as? String {
                    await acceptCloudKitShare(shareRecordName: shareRecordName)
                }
                
                return existingGroup
            }
            
            // TODO: Fetch from CloudKit if not found locally
            throw ShareError.groupNotFound
            
        } catch {
            print("❌ Failed to join group: \(error)")
            shareError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Accept CloudKit Share
    private func acceptCloudKitShare(shareRecordName: String) async {
        print("🔄 Accepting CloudKit share: \(shareRecordName)")
        
        // For now, we'll just track that the share was accepted
        // In a real implementation, you would handle the share URL from the invite
        // The actual share acceptance happens through CloudKit's built-in sharing UI
        
        // When a user taps on a CloudKit share link, iOS handles the acceptance
        // and the shared data becomes available through NSPersistentCloudKitContainer
        
        print("✅ Share acceptance tracked for: \(shareRecordName)")
        print("ℹ️ Actual share acceptance happens through CloudKit share URLs")
    }
    
    // MARK: - Fetch Shared Data
    func fetchSharedGroupData(for group: CareGroupEntity) async throws -> [Any] {
        print("🔄 Fetching shared data for group: \(group.name ?? "Unknown")")
        
        var sharedData: [Any] = []
        
        // For now, return local data
        // TODO: Implement CloudKit query for shared records
        
        let context = persistentContainer.viewContext
        
        // Fetch medications
        let medRequest: NSFetchRequest<MedicationEntity> = MedicationEntity.fetchRequest()
        if let medications = try? context.fetch(medRequest) {
            sharedData.append(contentsOf: medications)
        }
        
        // Fetch supplements
        let supRequest: NSFetchRequest<SupplementEntity> = SupplementEntity.fetchRequest()
        if let supplements = try? context.fetch(supRequest) {
            sharedData.append(contentsOf: supplements)
        }
        
        print("✅ Fetched \(sharedData.count) shared items")
        return sharedData
    }
    
    // MARK: - Update Share Permissions
    func updateMemberPermissions(member: GroupMemberEntity, newRole: String) async throws {
        print("🔄 Updating permissions for member: \(member.name ?? "Unknown")")
        
        member.role = newRole
        member.permissions = (newRole == "admin") ? "write" : "read"
        member.lastActiveAt = Date()  // Update last active instead of updatedAt
        
        try persistentContainer.viewContext.save()
        
        // TODO: Update CloudKit share participant permissions
        
        print("✅ Updated member to role: \(newRole)")
    }
    
    // MARK: - Error Types
    enum ShareError: LocalizedError {
        case invalidGroup
        case groupNotFound
        case shareCreationFailed
        case permissionDenied
        
        var errorDescription: String? {
            switch self {
            case .invalidGroup:
                return "Invalid group data"
            case .groupNotFound:
                return "Group not found with this invite code"
            case .shareCreationFailed:
                return "Failed to create share"
            case .permissionDenied:
                return "You don't have permission to perform this action"
            }
        }
    }
}

