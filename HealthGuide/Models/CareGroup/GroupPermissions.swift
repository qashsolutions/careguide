//
//  GroupPermissions.swift
//  HealthGuide
////
//  GroupPermissions.swift
//  HealthGuide/Models/CareGroup/GroupPermissions.swift
//
//  Role-based permissions and settings for family groups
//  App Store compliant with health data privacy controls
//

import Foundation

// MARK: - Member Role
@available(iOS 18.0, *)
enum MemberRole: String, CaseIterable, Codable, Sendable {
    case admin = "Admin"
    case caregiver = "Caregiver"
    case member = "Family Member"
    
    var icon: String {
        switch self {
        case .admin: return "crown.fill"
        case .caregiver: return "heart.text.square.fill"
        case .member: return "person.fill"
        }
    }
    
    var defaultPermissions: MemberPermissions {
        switch self {
        case .admin: return .fullAccess
        case .caregiver: return .editHealth
        case .member: return .readOnly
        }
    }
}

// MARK: - Member Permissions
@available(iOS 18.0, *)
enum MemberPermissions: String, Codable, Sendable {
    case fullAccess = "Full Access"
    case editHealth = "Edit Health Data"
    case readOnly = "Read Only"
    
    var canEdit: Bool {
        self != .readOnly
    }
    
    var canManageGroup: Bool {
        self == .fullAccess
    }
    
    var description: String {
        switch self {
        case .fullAccess:
            return "Can manage group and edit all health data"
        case .editHealth:
            return "Can edit health data but not manage group"
        case .readOnly:
            return "Can view health data only"
        }
    }
}

// MARK: - Group Settings
@available(iOS 18.0, *)
struct GroupSettings: Codable, Hashable, Sendable {
    var allowNotifications: Bool = true
    var shareConflictAlerts: Bool = true
    var requireAdminApproval: Bool = true
    var autoExpireInvites: Bool = true
    var notifyOnMedicationChanges: Bool = true
    var notifyOnMissedDoses: Bool = true
    
    /// Default privacy-focused settings for App Store compliance
    static let `default` = GroupSettings()
    
    /// High security settings for sensitive health data
    static let highSecurity = GroupSettings(
        allowNotifications: false,
        shareConflictAlerts: false,
        requireAdminApproval: true,
        autoExpireInvites: true,
        notifyOnMedicationChanges: false,
        notifyOnMissedDoses: false
    )
}
