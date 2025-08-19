//
//  CoreDataManager+Group.swift
//  HealthGuide
//
//  Care group management operations
//  Handles groups, members, and invite codes
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Group Operations
    
    /// Save a care group to the persistent store
    func saveGroup(_ group: CareGroup) async throws {
        // Validate the group
        try group.validate()
        
        try await context.perform { [context] in
            let entity = CareGroupEntity(context: context)
            entity.id = group.id
            entity.name = group.name
            entity.inviteCode = group.inviteCode
            entity.adminUserID = group.adminUserID
            entity.createdAt = group.createdAt
            entity.updatedAt = Date()
            entity.inviteCodeExpiry = group.inviteCodeExpiry
            
            // Convert settings to dictionary
            let settingsDict: [String: Bool] = [
                "allowNotifications": group.settings.allowNotifications,
                "shareConflictAlerts": group.settings.shareConflictAlerts,
                "requireAdminApproval": group.settings.requireAdminApproval,
                "autoExpireInvites": group.settings.autoExpireInvites,
                "notifyOnMedicationChanges": group.settings.notifyOnMedicationChanges,
                "notifyOnMissedDoses": group.settings.notifyOnMissedDoses
            ]
            entity.settings = settingsDict as NSDictionary
            
            try context.save()
        }
        
        // Post notification on main queue to avoid threading issues
        await MainActor.run {
            // COMMENTED OUT: Old generic notification causing CPU issues
            // NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
            
            // NEW: Post selective notification for group changes only
            NotificationCenter.default.post(name: .groupDataDidChange, object: nil)
        }
    }
    
    /// Update an existing care group
    func updateGroup(_ group: CareGroup) async throws {
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", group.id as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                throw AppError.coreDataFetchFailed
            }
            
            entity.name = group.name
            entity.inviteCode = group.inviteCode
            entity.adminUserID = group.adminUserID
            entity.updatedAt = Date()
            entity.inviteCodeExpiry = group.inviteCodeExpiry
            
            // Update settings
            let settingsDict: [String: Bool] = [
                "allowNotifications": group.settings.allowNotifications,
                "shareConflictAlerts": group.settings.shareConflictAlerts,
                "requireAdminApproval": group.settings.requireAdminApproval,
                "autoExpireInvites": group.settings.autoExpireInvites,
                "notifyOnMedicationChanges": group.settings.notifyOnMedicationChanges,
                "notifyOnMissedDoses": group.settings.notifyOnMissedDoses
            ]
            entity.settings = settingsDict as NSDictionary
            
            try context.save()
        }
        
        // Post notification on main queue to avoid threading issues
        await MainActor.run {
            // COMMENTED OUT: Old generic notification causing CPU issues
            // NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
            
            // NEW: Post selective notification for group changes only
            NotificationCenter.default.post(name: .groupDataDidChange, object: nil)
        }
    }
    
    /// Fetch all care groups
    func fetchGroups() async throws -> [CareGroup] {
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { CoreDataManager.convertToGroup($0) }
        }
    }
    
    /// Fetch group permissions data (Sendable-safe)
    struct GroupPermissionData: Sendable {
        let groupID: UUID
        let adminDeviceID: String?
        let members: [MemberPermissionData]
    }
    
    struct MemberPermissionData: Sendable {
        let userID: String?
        let role: String?
    }
    
    /// Fetch group permission data by ID (Swift 6 Sendable-safe)
    func fetchGroupPermissions(by id: UUID) async throws -> GroupPermissionData? {
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.relationshipKeyPathsForPrefetching = ["members"]
            
            guard let entity = try context.fetch(request).first else {
                return nil
            }
            
            // Extract only the data we need (all Sendable types)
            let members = (entity.members as? Set<GroupMemberEntity>)?.compactMap { member in
                MemberPermissionData(
                    userID: member.userID?.uuidString,
                    role: member.role
                )
            } ?? []
            
            return GroupPermissionData(
                groupID: id,
                adminDeviceID: entity.adminUserID?.uuidString,
                members: members
            )
        }
    }
    
    /// Find a group by invite code
    func findGroup(byInviteCode code: String) async throws -> CareGroup? {
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "inviteCode == %@", code)
            
            guard let entity = try context.fetch(request).first else {
                return nil
            }
            
            return CoreDataManager.convertToGroup(entity)
        }
    }
    
    /// Delete a care group
    func deleteGroup(_ id: UUID) async throws {
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            if let entity = try context.fetch(request).first {
                // Delete all associated members first
                if let members = entity.members {
                    for case let member as NSManagedObject in members {
                        context.delete(member)
                    }
                }
                
                context.delete(entity)
                try context.save()
            }
        }
        
        await MainActor.run {
            // COMMENTED OUT: Old generic notification causing CPU issues
            // NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
            
            // NEW: Post selective notification for group changes only
            NotificationCenter.default.post(name: .groupDataDidChange, object: nil)
        }
    }
    
    /// Generate a new invite code for a group
    func generateInviteCode(for groupId: UUID) async throws -> String {
        // Generate code outside of Core Data context to avoid database lock
        let newCode = CoreDataManager.generateUniqueInviteCode()
        
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                throw AppError.coreDataFetchFailed
            }
            
            entity.inviteCode = newCode
            entity.inviteCodeExpiry = Calendar.current.date(
                byAdding: .day,
                value: 1,  // Configuration.FamilyGroups.inviteCodeExpiration is in hours, not days
                to: Date()
            )
            entity.updatedAt = Date()
            
            try context.save()
        }
        
        return newCode
    }
    
    /// Check if user is admin of a group
    func isUserAdmin(userId: String, groupId: UUID) async throws -> Bool {
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                return false
            }
            
            return entity.adminUserID?.uuidString == userId
        }
    }
    
    /// Add a member to a group
    func addMemberToGroup(groupId: UUID, userId: UUID, name: String, phone: String) async throws {
        try await context.perform { [context] in
            // Find the group
            let groupRequest = CareGroupEntity.fetchRequest()
            groupRequest.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
            
            guard let groupEntity = try context.fetch(groupRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            // Check if user is already a member
            if let members = groupEntity.members as? Set<GroupMemberEntity> {
                if members.contains(where: { $0.userID == userId }) {
                    throw AppError.alreadyInGroup
                }
                
                // Check member limit (2 members + 1 admin = 3 total)
                if members.count >= 2 {
                    throw AppError.groupFull(maxMembers: 3)
                }
            }
            
            // Create new member using Core Data's generated method
            let memberEntity = GroupMemberEntity(context: context)
            memberEntity.userID = userId
            memberEntity.name = name.isEmpty ? "Member" : name
            memberEntity.phoneNumber = phone
            
            // Add to group using Core Data's generated method
            groupEntity.addToMembers(memberEntity)
            groupEntity.updatedAt = Date()
            
            try context.save()
        }
        
        // Post notification on main queue to avoid threading issues
        await MainActor.run {
            // COMMENTED OUT: Old generic notification causing CPU issues
            // NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
            
            // NEW: Post selective notification for group changes only
            NotificationCenter.default.post(name: .groupDataDidChange, object: nil)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Convert CareGroupEntity to CareGroup model
    static func convertToGroup(_ entity: CareGroupEntity) -> CareGroup? {
        guard let id = entity.id,
              let name = entity.name,
              let adminUserID = entity.adminUserID else { return nil }
        
        // Parse settings - break into steps to avoid compiler timeout
        let settingsDict = entity.settings as? [String: Bool] ?? [:]
        let allowNotifications = settingsDict["allowNotifications"] ?? true
        let shareConflictAlerts = settingsDict["shareConflictAlerts"] ?? true
        let requireAdminApproval = settingsDict["requireAdminApproval"] ?? false
        let autoExpireInvites = settingsDict["autoExpireInvites"] ?? true
        let notifyOnMedicationChanges = settingsDict["notifyOnMedicationChanges"] ?? true
        let notifyOnMissedDoses = settingsDict["notifyOnMissedDoses"] ?? true
        
        let settings = GroupSettings(
            allowNotifications: allowNotifications,
            shareConflictAlerts: shareConflictAlerts,
            requireAdminApproval: requireAdminApproval,
            autoExpireInvites: autoExpireInvites,
            notifyOnMedicationChanges: notifyOnMedicationChanges,
            notifyOnMissedDoses: notifyOnMissedDoses
        )
        
        return CareGroup(
            id: id,
            name: name,
            adminUserID: adminUserID,
            settings: settings
        )
    }
    
    /// Generate a unique 6-character invite code
    private static func generateUniqueInviteCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}
