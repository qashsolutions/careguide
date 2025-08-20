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
        print("🔍 DEBUG: saveGroup called from async context")
        print("🔍 DEBUG: Group name: \(group.name), ID: \(group.id)")
        print("🔍 DEBUG: CoreDataManager context: \(context)")
        
        // Validate the group
        do {
            try group.validate()
            print("🔍 DEBUG: Group validation passed")
        } catch {
            print("🔍 DEBUG: ❌ Group validation failed: \(error)")
            throw error
        }
        
        let groupName = group.name
        let groupId = group.id
        
        print("🔍 DEBUG: About to call context.perform")
        
        // Perform Core Data operations with debug logging
        try await context.perform { [context] in
            print("🔍 DEBUG: Inside context.perform block")
            print("🔍 DEBUG: Context: \(context)")
            print("🔍 DEBUG: Context concurrency type: \(context.concurrencyType.rawValue)")
            
            // Check if group already exists
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
            
            print("🔍 DEBUG: About to fetch existing groups")
            let existingGroups = try context.fetch(request)
            print("🔍 DEBUG: Found \(existingGroups.count) existing groups")
            
            let entity: CareGroupEntity
            
            if let existingGroup = existingGroups.first {
                // Update existing group
                entity = existingGroup
                print("🔍 DEBUG: Updating existing group")
            } else {
                // Create new group - ensure we're on the right context
                print("🔍 DEBUG: Creating new group entity")
                entity = NSEntityDescription.insertNewObject(forEntityName: "CareGroupEntity", into: context) as! CareGroupEntity
                entity.id = groupId
                print("🔍 DEBUG: New group entity created with ID: \(groupId)")
            }
            
            // Set all properties
            print("🔍 DEBUG: Setting entity properties")
            entity.name = group.name
            entity.inviteCode = group.inviteCode
            entity.adminUserID = group.adminUserID
            entity.createdAt = entity.createdAt ?? group.createdAt // Don't overwrite creation date if updating
            entity.updatedAt = Date()
            entity.inviteCodeExpiry = group.inviteCodeExpiry
            print("🔍 DEBUG: Basic properties set")
            
            // Convert settings to dictionary
            let settingsDict: [String: Bool] = [
                "allowNotifications": group.settings.allowNotifications,
                "shareConflictAlerts": group.settings.shareConflictAlerts,
                "requireAdminApproval": group.settings.requireAdminApproval,
                "autoExpireInvites": group.settings.autoExpireInvites,
                "notifyOnMedicationChanges": group.settings.notifyOnMedicationChanges,
                "notifyOnMissedDoses": group.settings.notifyOnMissedDoses
            ]
            print("🔍 DEBUG: Settings dictionary created: \(settingsDict)")
            entity.settings = settingsDict as NSDictionary
            print("🔍 DEBUG: Settings assigned to entity")
            
            // Save the context
            print("🔍 DEBUG: Context has changes: \(context.hasChanges)")
            if context.hasChanges {
                print("🔍 DEBUG: About to save context")
                print("🔍 DEBUG: Context persistent store coordinator: \(String(describing: context.persistentStoreCoordinator))")
                do {
                    try context.save()
                    print("🔍 DEBUG: ✅ Context save succeeded")
                } catch let error as NSError {
                    print("🔍 DEBUG: ❌ Context save failed with error: \(error)")
                    print("🔍 DEBUG: ❌ Error domain: \(error.domain)")
                    print("🔍 DEBUG: ❌ Error code: \(error.code)")
                    print("🔍 DEBUG: ❌ Error userInfo: \(error.userInfo)")
                    print("🔍 DEBUG: ❌ Error localizedDescription: \(error.localizedDescription)")
                    throw error
                }
            } else {
                print("🔍 DEBUG: No changes to save")
            }
        }
        
        // All UI updates happen AFTER Core Data operations complete
        await MainActor.run {
            AppLogger.main.info("✅ Group saved to Core Data: \(groupName)")
            
            // Post notification for group changes
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
        
        // UI updates after Core Data operations
        await MainActor.run {
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
        let groupName = "Group-\(id.uuidString.prefix(8))" // For logging
        
        try await context.perform { [context] in
            let request = CareGroupEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            let entities = try context.fetch(request)
            
            guard let entity = entities.first else {
                return // No group found, nothing to delete
            }
            
            // Delete all associated members first
            if let members = entity.members as? Set<GroupMemberEntity> {
                for member in members {
                    context.delete(member)
                }
            }
            
            // Delete the group entity
            context.delete(entity)
            
            // Save changes
            if context.hasChanges {
                try context.save()
            }
        }
        
        // UI updates after Core Data operations
        await MainActor.run {
            AppLogger.main.info("✅ Group deleted successfully: \(groupName)")
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
                value: 1,
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
        let memberName = name.isEmpty ? "Member" : name
        
        // Core Data operations without any logging inside
        try await context.perform { [context] in
            // Find the group
            let groupRequest = CareGroupEntity.fetchRequest()
            groupRequest.predicate = NSPredicate(format: "id == %@", groupId as CVarArg)
            
            let groups = try context.fetch(groupRequest)
            
            guard let groupEntity = groups.first else {
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
            
            // Create new member using NSEntityDescription for thread safety
            let memberEntity = NSEntityDescription.insertNewObject(forEntityName: "GroupMemberEntity", into: context) as! GroupMemberEntity
            memberEntity.userID = userId
            memberEntity.name = memberName
            memberEntity.phoneNumber = phone
            
            // Add to group using Core Data's generated method
            groupEntity.addToMembers(memberEntity)
            groupEntity.updatedAt = Date()
            
            // Save changes
            if context.hasChanges {
                try context.save()
            }
        }
        
        // UI updates after Core Data operations
        await MainActor.run {
            AppLogger.main.info("✅ Member '\(memberName)' added to group successfully")
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
