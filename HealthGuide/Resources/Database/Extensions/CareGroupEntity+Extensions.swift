//
//  CareGroupEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for CareGroupEntity with CloudKit default values
//  Production-ready implementation for health app
//

import Foundation
import CoreData

// MARK: - Additional Notification Names
extension Notification.Name {
    static let coreDataEntityNeedsUserID = Notification.Name("coreDataEntityNeedsUserID")
}

@available(iOS 18.0, *)
extension CareGroupEntity {
    
    /// Called when entity is first inserted into context
    /// Sets default values for required fields to ensure CloudKit compatibility
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Only set values if they haven't been set already
        if id == nil {
            id = UUID()
            #if DEBUG
            print("🏥 CareGroupEntity: Generated ID: \(id!)")
            #endif
        }
        
        if adminUserID == nil {
            // Since UserManager is @MainActor, we need to handle this differently
            // For now, generate a UUID and let the app update it later if needed
            adminUserID = UUID()
            
            #if DEBUG
            print("👤 CareGroupEntity: Generated temporary admin ID (will sync with user later)")
            #endif
            
            // Post notification to update with actual user ID when possible
            NotificationCenter.default.post(
                name: .coreDataEntityNeedsUserID,
                object: nil,
                userInfo: [
                    "entity": "CareGroupEntity",
                    "entityID": id!,
                    "field": "adminUserID",
                    "temporaryID": adminUserID!
                ]
            )
        }
        
        if createdAt == nil {
            createdAt = Date()
        }
        
        if inviteCode == nil {
            inviteCode = InviteCodeGenerator.generateSecureCode()
            #if DEBUG
            print("🔐 CareGroupEntity: Generated invite code: \(inviteCode!)")
            #endif
        }
        
        if inviteCodeExpiry == nil, let created = createdAt {
            // Set expiry to 30 days from creation
            inviteCodeExpiry = Calendar.current.date(byAdding: .day, value: 30, to: created)
        }
        
        // Initialize with empty settings if needed
        if settings == nil {
            settings = NSDictionary()
        }
        
        #if DEBUG
        print("✅ CareGroupEntity: awakeFromInsert completed for \(name ?? "unnamed group")")
        #endif
    }
    
    /// Regenerate invite code with new expiry
    public func regenerateInviteCode() {
        inviteCode = InviteCodeGenerator.generateSecureCode()
        inviteCodeExpiry = Calendar.current.date(byAdding: .day, value: 30, to: Date())
        updatedAt = Date()
        #if DEBUG
        print("🔄 CareGroupEntity: Regenerated invite code: \(inviteCode!)")
        #endif
    }
    
    /// Check if invite code is still valid
    public var isInviteCodeValid: Bool {
        guard let expiry = inviteCodeExpiry else { return false }
        return expiry > Date()
    }
    
    // MARK: - Member Management
    
    /// Get the super admin member (original creator)
    public var superAdminMember: GroupMemberEntity? {
        guard let members = members as? Set<GroupMemberEntity> else { return nil }
        return members.first { $0.isSuperAdmin }
    }
    
    /// Get the current content admin member
    public var contentAdminMember: GroupMemberEntity? {
        guard let members = members as? Set<GroupMemberEntity> else { return nil }
        return members.first { $0.isContentAdmin }
    }
    
    /// Get all regular members (non-admin)
    public var regularMembers: [GroupMemberEntity] {
        guard let members = members as? Set<GroupMemberEntity> else { return [] }
        return members.filter { !$0.isSuperAdmin && !$0.isContentAdmin }
    }
    
    /// Assign content admin role to a member (only super admin can do this)
    /// Automatically demotes current content admin to regular member
    @discardableResult
    public func assignContentAdmin(to newAdmin: GroupMemberEntity, by requestingUser: GroupMemberEntity) -> Bool {
        // Only super admin can assign content admin role
        guard requestingUser.isSuperAdmin else {
            #if DEBUG
            print("❌ CareGroupEntity: Only super admin can assign content admin role")
            #endif
            return false
        }
        
        // Cannot make super admin a content admin
        guard !newAdmin.isSuperAdmin else {
            #if DEBUG
            print("❌ CareGroupEntity: Cannot change super admin role")
            #endif
            return false
        }
        
        // If there's a current content admin, demote them to member
        if let currentContentAdmin = contentAdminMember {
            currentContentAdmin.role = GroupMemberEntity.MemberRole.member.rawValue
            #if DEBUG
            print("↓ CareGroupEntity: Demoted \(currentContentAdmin.name ?? "member") from content admin to member")
            #endif
        }
        
        // Promote the new member to content admin
        newAdmin.role = GroupMemberEntity.MemberRole.contentAdmin.rawValue
        updatedAt = Date()
        
        #if DEBUG
        print("↑ CareGroupEntity: Promoted \(newAdmin.name ?? "member") to content admin")
        #endif
        
        return true
    }
    
    /// Remove content admin role (reverts to regular member)
    @discardableResult
    public func removeContentAdmin(by requestingUser: GroupMemberEntity) -> Bool {
        // Only super admin can remove content admin role
        guard requestingUser.isSuperAdmin else {
            #if DEBUG
            print("❌ CareGroupEntity: Only super admin can remove content admin role")
            #endif
            return false
        }
        
        // Find and demote current content admin
        if let currentContentAdmin = contentAdminMember {
            currentContentAdmin.role = GroupMemberEntity.MemberRole.member.rawValue
            updatedAt = Date()
            
            #if DEBUG
            print("↓ CareGroupEntity: Removed content admin role from \(currentContentAdmin.name ?? "member")")
            #endif
            
            return true
        }
        
        return false
    }
    
    /// Check if a user can edit content in this group
    public func userCanEditContent(userID: UUID) -> Bool {
        guard let members = members as? Set<GroupMemberEntity> else { return false }
        
        // Find the member with matching userID
        guard let member = members.first(where: { $0.userID == userID }) else { return false }
        
        return member.canEditContent
    }
    
    /// Check if a user is the super admin of this group
    public func isSuperAdmin(userID: UUID) -> Bool {
        return adminUserID == userID
    }
}