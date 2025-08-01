
//  GroupMember.swift
//  HealthGuide/Models/CareGroup/GroupMember.swift
//
//  Family group member model with privacy-compliant data handling
//  Swift 6 actor-safe with Sendable conformance
//

import Foundation
import SwiftUI

// MARK: - Group Member
@available(iOS 18.0, *)
struct GroupMember: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var userID: UUID
    var name: String
    var email: String?
    var phoneNumber: String?
    var role: MemberRole
    var permissions: MemberPermissions
    let joinedAt: Date
    var lastActiveAt: Date
    var profileColor: String
    
    init(
        id: UUID = UUID(),
        userID: UUID = UUID(),
        name: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        role: MemberRole = .member,
        permissions: MemberPermissions = .readOnly
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.permissions = permissions
        self.joinedAt = Date()
        self.lastActiveAt = Date()
        self.profileColor = GroupMember.generateProfileColor()
    }
}

// MARK: - Profile Color Management
@available(iOS 18.0, *)
extension GroupMember {
    /// Generate random profile color from predefined safe palette
    static func generateProfileColor() -> String {
        let colors = [
            "#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4",
            "#FECA57", "#DDA0DD", "#98D8C8", "#F7DC6F",
            "#BB8FCE", "#85C1F2", "#F8B500", "#6C5CE7"
        ]
        return colors.randomElement() ?? "#007AFF"
    }
    
    /// Convert hex string to SwiftUI Color
    var profileColorValue: Color {
        Color(hex: profileColor)
    }
}

// MARK: - Member Validation
@available(iOS 18.0, *)
extension GroupMember {
    /// Validate member data for App Store compliance
    func validate() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedName.count >= 2 else {
            throw AppError.nameTooShort(minimum: 2)
        }
        
        guard trimmedName.count <= 50 else {
            throw AppError.nameTooLong(maximum: 50)
        }
        
        // Email validation if provided
        if let email = email, !email.isEmpty {
            guard email.contains("@") && email.contains(".") else {
                throw AppError.invalidCharacters(field: "Email")
            }
        }
        
        // Phone validation if provided
        if let phone = phoneNumber, !phone.isEmpty {
            let phoneRegex = "^[+]?[0-9\\s\\-\\(\\)]{10,}$"
            let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
            guard phoneTest.evaluate(with: phone) else {
                throw AppError.invalidCharacters(field: "Phone number")
            }
        }
    }
    
    /// Update member's last active timestamp
    mutating func updateLastActive() {
        lastActiveAt = Date()
    }
    
    /// Check if member has been active recently
    var isRecentlyActive: Bool {
        let daysSinceLastActive = Calendar.current.dateComponents([.day], from: lastActiveAt, to: Date()).day ?? 0
        return daysSinceLastActive <= 7
    }
}

// MARK: - Sample Data
@available(iOS 18.0, *)
extension GroupMember {
    static let sampleAdmin = GroupMember(
        name: "Mary Johnson",
        email: "mary@email.com",
        role: .admin,
        permissions: .fullAccess
    )
    
    static let sampleCaregiver = GroupMember(
        name: "John Johnson Jr",
        email: "john@email.com",
        role: .caregiver,
        permissions: .editHealth
    )
    
    static let sampleMember = GroupMember(
        name: "Sarah Johnson",
        phoneNumber: "+1234567890",
        role: .member,
        permissions: .readOnly
    )
}
