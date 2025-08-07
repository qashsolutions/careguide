//
//  GroupMemberEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for GroupMemberEntity with CloudKit default values
//  Production-ready implementation for care group member management
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension GroupMemberEntity {
    
    // MARK: - Member Roles
    public enum MemberRole: String, CaseIterable, Sendable {
        case superAdmin = "super_admin"  // Original creator - full control
        case contentAdmin = "content_admin"  // Can edit content only
        case member = "member"  // View-only access
        
        /// Default role for new members
        static let defaultRole = MemberRole.member
        
        /// Display name for UI
        var displayName: String {
            switch self {
            case .superAdmin: return "Super Admin"
            case .contentAdmin: return "Content Admin"
            case .member: return "Member"
            }
        }
        
        /// Icon name for UI
        var iconName: String {
            switch self {
            case .superAdmin: return "star.circle.fill"  // Star for super admin
            case .contentAdmin: return "pencil.circle.fill"  // Pencil for content editing
            case .member: return "person.circle"  // Person for regular member
            }
        }
        
        /// Icon color for UI
        var iconColor: Color {
            switch self {
            case .superAdmin: return AppTheme.Colors.warningOrange
            case .contentAdmin: return AppTheme.Colors.primaryBlue
            case .member: return AppTheme.Colors.textSecondary
            }
        }
        
        /// Can this role edit content?
        var canEditContent: Bool {
            switch self {
            case .superAdmin, .contentAdmin: return true
            case .member: return false
            }
        }
        
        /// Can this role manage members?
        var canManageMembers: Bool {
            return self == .superAdmin
        }
    }
    
    // MARK: - Member Permissions
    public enum MemberPermission: String, CaseIterable, Sendable {
        case read = "read"
        case write = "write"
        case delete = "delete"
        
        /// Default permission for new members
        static let defaultPermission = MemberPermission.read
    }
    
    // MARK: - Profile Colors
    public enum ProfileColor: String, CaseIterable, Sendable {
        case blue = "blue"
        case green = "green"
        case purple = "purple"
        case orange = "orange"
        case pink = "pink"
        case teal = "teal"
        case red = "red"
        case yellow = "yellow"
        
        /// Get random color for new members
        static func random() -> ProfileColor {
            return allCases.randomElement() ?? .blue
        }
        
        /// SwiftUI Color
        var color: Color {
            return Color(self.rawValue)
        }
    }
    
    // MARK: - awakeFromInsert
    /// Called when entity is first inserted into context
    /// Sets default values for required fields to ensure CloudKit compatibility
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Generate unique ID
        if id == nil {
            id = UUID()
            #if DEBUG
            print("👥 GroupMemberEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set user ID with error handling
        if userID == nil {
            // Since UserManager is @MainActor, we need to handle this differently
            // For now, generate a UUID and let the app update it later if needed
            userID = UUID()
            
            #if DEBUG
            print("👤 GroupMemberEntity: Generated temporary user ID (will sync with user later)")
            #endif
            
            // Post notification to update with actual user ID when possible
            NotificationCenter.default.post(
                name: .coreDataEntityNeedsUserID,
                object: nil,
                userInfo: [
                    "entity": "GroupMemberEntity",
                    "entityID": id!,
                    "field": "userID",
                    "temporaryID": userID!
                ]
            )
        }
        
        // Set timestamps
        if joinedAt == nil {
            joinedAt = Date()
            #if DEBUG
            print("📅 GroupMemberEntity: Set join date")
            #endif
        }
        
        if lastActiveAt == nil {
            lastActiveAt = Date()
        }
        
        // Set role with validation
        if role == nil {
            role = MemberRole.defaultRole.rawValue
            #if DEBUG
            print("👤 GroupMemberEntity: Set default role: \(role!)")
            #endif
        } else {
            validateAndFixRole()
        }
        
        // Set permissions with validation
        if permissions == nil {
            permissions = MemberPermission.defaultPermission.rawValue
            #if DEBUG
            print("🔐 GroupMemberEntity: Set default permission: \(permissions!)")
            #endif
        } else {
            validateAndFixPermissions()
        }
        
        // Set profile color
        if profileColor == nil {
            profileColor = ProfileColor.random().rawValue
            #if DEBUG
            print("🎨 GroupMemberEntity: Set profile color: \(profileColor!)")
            #endif
        }
        
        #if DEBUG
        print("✅ GroupMemberEntity: awakeFromInsert completed for \(name ?? "unnamed member")")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes role value if corrupted
    private func validateAndFixRole() {
        guard let currentRole = role else { return }
        
        let validRoles = MemberRole.allCases.map { $0.rawValue }
        if !validRoles.contains(currentRole) {
            let oldValue = currentRole
            role = MemberRole.defaultRole.rawValue
            
            #if DEBUG
            print("⚠️ GroupMemberEntity: Invalid role '\(oldValue)' fixed to '\(role!)'")
            #endif
            
            // Post notification for error tracking
            NotificationCenter.default.post(
                name: .coreDataEntityError,
                object: nil,
                userInfo: [
                    "entity": "GroupMemberEntity",
                    "field": "role",
                    "error": "Invalid role value: \(oldValue)",
                    "fallbackValue": role!,
                    "action": "validation_fix"
                ]
            )
        }
    }
    
    /// Validates and fixes permissions value if corrupted
    private func validateAndFixPermissions() {
        guard let currentPermissions = permissions else { return }
        
        let validPermissions = MemberPermission.allCases.map { $0.rawValue }
        if !validPermissions.contains(currentPermissions) {
            let oldValue = currentPermissions
            permissions = MemberPermission.defaultPermission.rawValue
            
            #if DEBUG
            print("⚠️ GroupMemberEntity: Invalid permission '\(oldValue)' fixed to '\(permissions!)'")
            #endif
            
            // Post notification for error tracking
            NotificationCenter.default.post(
                name: .coreDataEntityError,
                object: nil,
                userInfo: [
                    "entity": "GroupMemberEntity",
                    "field": "permissions",
                    "error": "Invalid permission value: \(oldValue)",
                    "fallbackValue": permissions!,
                    "action": "validation_fix"
                ]
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Update last active timestamp
    public func updateLastActive() {
        lastActiveAt = Date()
        #if DEBUG
        print("⏰ GroupMemberEntity: Updated last active time")
        #endif
    }
    
    /// Get role as enum
    public var roleEnum: MemberRole? {
        guard let roleString = role else { return nil }
        return MemberRole(rawValue: roleString)
    }
    
    /// Check if member is super admin
    public var isSuperAdmin: Bool {
        return roleEnum == .superAdmin
    }
    
    /// Check if member is content admin
    public var isContentAdmin: Bool {
        return roleEnum == .contentAdmin
    }
    
    /// Check if member can edit content (super admin or content admin)
    public var canEditContent: Bool {
        return roleEnum?.canEditContent ?? false
    }
    
    /// Check if member can manage other members (only super admin)
    public var canManageMembers: Bool {
        return roleEnum?.canManageMembers ?? false
    }
    
    /// Check if member is admin (legacy - now checks for any admin role)
    public var isAdmin: Bool {
        return isSuperAdmin || isContentAdmin
    }
    public var memberRole: MemberRole? {
        guard let role = role else { return nil }
        return MemberRole(rawValue: role)
    }
    
    /// Get permission as enum
    public var memberPermission: MemberPermission? {
        guard let permissions = permissions else { return nil }
        return MemberPermission(rawValue: permissions)
    }
    
    /// Get profile color as enum
    public var memberProfileColor: ProfileColor? {
        guard let profileColor = profileColor else { return nil }
        return ProfileColor(rawValue: profileColor)
    }
    
    /// Get SwiftUI Color for profile
    public var profileSwiftUIColor: Color {
        return memberProfileColor?.color ?? Color.gray
    }
    
    /// Update role with validation
    public func setRole(_ newRole: MemberRole) {
        role = newRole.rawValue
        lastActiveAt = Date()
        
        #if DEBUG
        print("👑 GroupMemberEntity: Updated role to \(newRole.rawValue)")
        #endif
    }
    
    /// Update permissions with validation
    public func setPermissions(_ newPermission: MemberPermission) {
        permissions = newPermission.rawValue
        lastActiveAt = Date()
        
        #if DEBUG
        print("🔐 GroupMemberEntity: Updated permissions to \(newPermission.rawValue)")
        #endif
    }
    
    /// Check if member has been inactive for specified days
    public func isInactive(days: Int = 30) -> Bool {
        guard let lastActive = lastActiveAt else { return true }
        let daysSinceActive = Calendar.current.dateComponents([.day], 
                                                             from: lastActive, 
                                                             to: Date()).day ?? 0
        return daysSinceActive > days
    }
    
    /// Format member display name
    public var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        } else if let email = email, !email.isEmpty {
            return email
        } else if let phone = phoneNumber, !phone.isEmpty {
            return phone
        } else {
            return "Unknown Member"
        }
    }
    
    /// Get member initials for avatar
    public var initials: String {
        let displayName = self.displayName
        let components = displayName.components(separatedBy: " ")
        
        if components.count >= 2 {
            // First letter of first and last name
            let first = components.first?.prefix(1) ?? ""
            let last = components.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        } else {
            // First two letters of single name
            return String(displayName.prefix(2)).uppercased()
        }
    }
    
    /// Check if member can perform action based on permissions
    public func canPerform(action: MemberPermission) -> Bool {
        guard let currentPermission = memberPermission else { return false }
        
        switch action {
        case .read:
            return true // Everyone can read
        case .write:
            return currentPermission == .write || currentPermission == .delete
        case .delete:
            return currentPermission == .delete
        }
    }
}