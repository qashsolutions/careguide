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
}