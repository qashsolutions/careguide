//
//  CareGroup.swift
//  HealthGuide/Models/CareGroup/CareGroup.swift
//
//  Core family group model with privacy-compliant member management
//  App Store ready with proper data validation and security
//

import Foundation

// MARK: - Care Group
@available(iOS 18.0, *)
struct CareGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var inviteCode: String
    var adminUserID: UUID
    var members: [GroupMember]
    let createdAt: Date
    var updatedAt: Date
    var inviteCodeExpiry: Date
    var settings: GroupSettings
    
    init(
        id: UUID = UUID(),
        name: String,
        adminUserID: UUID,
        members: [GroupMember] = [],
        settings: GroupSettings = .default
    ) {
        self.id = id
        self.name = name
        self.inviteCode = CareGroup.generateInviteCode()
        self.adminUserID = adminUserID
        self.members = members
        self.createdAt = Date()
        self.updatedAt = Date()
        self.inviteCodeExpiry = Date().addingTimeInterval(
            TimeInterval(Configuration.FamilyGroups.inviteCodeExpiration * 3600)
        )
        self.settings = settings
    }
}

// MARK: - Group Properties
@available(iOS 18.0, *)
extension CareGroup {
    var isInviteCodeValid: Bool {
        inviteCodeExpiry > Date()
    }
    
    var memberCount: Int {
        members.count + 1
    }
    
    var isFull: Bool {
        memberCount >= Configuration.FamilyGroups.maxGroupMembers
    }
    
    var admin: GroupMember? {
        members.first { $0.userID == adminUserID }
    }
}

// MARK: - Group Management
@available(iOS 18.0, *)
extension CareGroup {
    mutating func regenerateInviteCode() {
        inviteCode = CareGroup.generateInviteCode()
        inviteCodeExpiry = Date().addingTimeInterval(
            TimeInterval(Configuration.FamilyGroups.inviteCodeExpiration * 3600)
        )
        updatedAt = Date()
    }
    
    mutating func addMember(_ member: GroupMember) throws {
        guard !isFull else {
            throw AppError.groupFull(maxMembers: Configuration.FamilyGroups.maxGroupMembers)
        }
        
        guard !members.contains(where: { $0.userID == member.userID }) else {
            throw AppError.alreadyInGroup
        }
        
        let validatedMember = member
        try validatedMember.validate()
        
        members.append(validatedMember)
        updatedAt = Date()
    }
    
    mutating func removeMember(userID: UUID) throws {
        guard userID != adminUserID else {
            throw AppError.notGroupAdmin
        }
        
        members.removeAll { $0.userID == userID }
        updatedAt = Date()
    }
    
    mutating func updateMemberRole(userID: UUID, newRole: MemberRole) throws {
        guard let index = members.firstIndex(where: { $0.userID == userID }) else {
            return
        }
        
        members[index].role = newRole
        members[index].permissions = newRole.defaultPermissions
        updatedAt = Date()
    }
}

// MARK: - Validation & Security
@available(iOS 18.0, *)
extension CareGroup {
    func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedName.count >= 2 else {
            throw AppError.nameTooShort(minimum: 2)
        }
        
        guard trimmedName.count <= 50 else {
            throw AppError.nameTooLong(maximum: 50)
        }
        
        guard memberCount <= Configuration.FamilyGroups.maxGroupMembers else {
            throw AppError.groupFull(maxMembers: Configuration.FamilyGroups.maxGroupMembers)
        }
        
        // Validate all members
        for member in members {
            try member.validate()
        }
    }
    
    static func generateInviteCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let numbers = "0123456789"
        
        var code = ""
        for i in 0..<Configuration.FamilyGroups.inviteCodeLength {
            let source = i % 2 == 0 ? letters : numbers
            code.append(source.randomElement() ?? (i % 2 == 0 ? "A" : "1"))
        }
        
        return code
    }
}

// MARK: - Sample Data
@available(iOS 18.0, *)
extension CareGroup {
    static let sampleGroup = CareGroup(
        name: "Johnson Family",
        adminUserID: UUID(),
        members: [
            .sampleAdmin,
            .sampleCaregiver,
            .sampleMember
        ]
    )
}
