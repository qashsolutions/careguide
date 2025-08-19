//
//  PermissionManager.swift
//  HealthGuide
//
//  Manages user permissions within care groups
//  Checks if current user can edit content based on their role
//

import Foundation
@preconcurrency import CoreData
import SwiftUI

@available(iOS 18.0, *)
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var currentUserCanEdit = false
    @Published var currentUserRole: GroupMemberEntity.MemberRole = .member
    @Published var isInGroup = false
    
    // Store references to avoid repeated access
    private let coreDataManager = CoreDataManager.shared
    private let keychainService = KeychainService.shared
    private let deviceCheckManager = DeviceCheckManager.shared
    
    // Cache to prevent redundant checks
    private var lastCheckedGroupID: String?
    private var lastCheckTime: Date = .distantPast
    private var currentDeviceID: String?
    
    // Use nonisolated init to prevent actor isolation issues
    nonisolated private init() {
        // Defer initialization work to avoid blocking
        Task { @MainActor in
            await self.checkCurrentUserPermissions()
        }
    }
    
    /// Check if current user can edit content based on device ID
    func checkCurrentUserPermissions() async {
        // Get device ID (persistent across reinstalls)
        if currentDeviceID == nil {
            currentDeviceID = await deviceCheckManager.getDeviceIdentifier()
        }
        
        guard let deviceID = currentDeviceID else {
            print("❌ No device ID available")
            currentUserCanEdit = true // Default to solo mode
            isInGroup = false
            return
        }
        
        // Get active group ID
        let activeGroupID = UserDefaults.standard.string(forKey: "activeGroupID")
        
        // Skip if we recently checked the same group (within 5 seconds)
        if let lastGroupID = lastCheckedGroupID,
           lastGroupID == activeGroupID,
           Date().timeIntervalSince(lastCheckTime) < 5 {
            return // Use cached values
        }
        
        // Update cache markers
        lastCheckedGroupID = activeGroupID
        lastCheckTime = Date()
        
        guard let activeGroupID = activeGroupID,
              let groupUUID = UUID(uuidString: activeGroupID) else {
            // No active group - user can edit (solo mode)
            currentUserCanEdit = true
            isInGroup = false
            return
        }
        
        do {
            // Query Core Data using Sendable-safe data transfer
            let groupPermissions = try await coreDataManager.fetchGroupPermissions(by: groupUUID)
            
            guard let groupPermissions = groupPermissions else {
                // Group not found
                currentUserCanEdit = true
                isInGroup = false
                return
            }
            
            isInGroup = true
            
            // Check if this device is the super admin (group creator)
            if let adminDeviceID = groupPermissions.adminDeviceID,
               adminDeviceID == deviceID {
                currentUserRole = .superAdmin
                currentUserCanEdit = true
                print("✅ Device is super admin")
                return
            }
            
            // Check member role from permissions data
            if let member = groupPermissions.members.first(where: { $0.userID == deviceID }) {
                if let roleString = member.role,
                   let role = GroupMemberEntity.MemberRole(rawValue: roleString) {
                    currentUserRole = role
                    currentUserCanEdit = role.canEditContent
                    print("✅ Device role: \(role.rawValue)")
                } else {
                    currentUserRole = .member
                    currentUserCanEdit = false
                }
            } else {
                // Device not in members - default to read-only
                currentUserRole = .member
                currentUserCanEdit = false
                print("⚠️ Device not found in group members")
            }
        } catch {
            print("❌ Failed to check permissions: \(error)")
            // On error, default to solo mode
            currentUserCanEdit = true
            isInGroup = false
        }
    }
    
    /// Show alert when user without edit permissions tries to edit
    func showNoEditPermissionAlert() -> Alert {
        Alert(
            title: Text("View Only Access"),
            message: Text("Contact your group admin to make changes"),
            dismissButton: .default(Text("OK"))
        )
    }
    
    /// Get permission message for UI
    var permissionMessage: String {
        if !isInGroup {
            return ""
        }
        
        switch currentUserRole {
        case .superAdmin:
            return "Super Admin - Full Access"
        case .contentAdmin:
            return "Admin - Can Edit Content"
        case .member:
            return "Member - View Only"
        }
    }
    
    /// Refresh permissions (call when group changes)
    func refreshPermissions() async {
        await checkCurrentUserPermissions()
    }
}