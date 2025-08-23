//
//  FirebaseGroupService.swift
//  HealthGuide
//
//  Manages Firebase Firestore group operations for cross-Apple ID sharing
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@available(iOS 18.0, *)
@MainActor
final class FirebaseGroupService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseGroupService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let authService = FirebaseAuthService.shared
    private var groupListeners: [String: ListenerRegistration] = [:]
    
    @Published var currentGroup: FirestoreGroup? {
        didSet {
            // Persist the current group ID when it changes
            if let group = currentGroup {
                UserDefaults.standard.set(group.id, forKey: "currentFirebaseGroupId")
                UserDefaults.standard.synchronize() // Force save immediately
                AppLogger.main.debug("Saved Firebase group to UserDefaults: \(group.name) with ID: \(group.id)")
                
                // Verify it was saved
                if let saved = UserDefaults.standard.string(forKey: "currentFirebaseGroupId") {
                    AppLogger.main.debug("✅ Verified group ID saved: \(saved)")
                } else {
                    AppLogger.main.error("❌ Failed to save group ID to UserDefaults!")
                }
                
                // Notify that group has changed (group is set)
                NotificationCenter.default.post(
                    name: .firebaseGroupDidChange,
                    object: nil,
                    userInfo: ["groupId": group.id]
                )
            } else {
                UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
                UserDefaults.standard.synchronize() // Force save immediately
                AppLogger.main.debug("Cleared Firebase group from UserDefaults")
                
                // Notify that group has changed (group was cleared)
                NotificationCenter.default.post(
                    name: .firebaseGroupDidChange,
                    object: nil
                )
            }
        }
    }
    @Published var groupMembers: [FirestoreMember] = []
    @Published var isSyncing = false
    @Published var syncError: String?
    
    // MARK: - Computed Properties
    
    /// Check if current user has write permission in the group
    var userHasWritePermission: Bool {
        guard let group = currentGroup,
              let userId = try? authService.getCurrentUserIdSync() else {
            return true // Default to true if no group (local mode)
        }
        return group.writePermissionIds.contains(userId)
    }
    
    /// Check if current user is an admin of the group
    var userIsAdmin: Bool {
        guard let group = currentGroup,
              let userId = try? authService.getCurrentUserIdSync() else {
            return true // Default to true if no group (local mode)
        }
        return group.adminIds.contains(userId)
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("FirebaseGroupService initialized")
        // Only load saved group if user explicitly has one
        // This prevents unnecessary network calls on startup
        Task {
            await loadSavedGroup()
        }
    }
    
    // MARK: - Debug Helper
    public func debugCheckUserDefaults() {
        print("🔍 DEBUG: Checking all UserDefaults keys...")
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        
        // Check for any group-related keys
        for (key, value) in dict where key.lowercased().contains("group") {
            print("   Found key: \(key) = \(value)")
        }
        
        // Specifically check our key
        if let groupId = defaults.string(forKey: "currentFirebaseGroupId") {
            print("   ✅ currentFirebaseGroupId = \(groupId)")
        } else {
            print("   ❌ currentFirebaseGroupId not found")
        }
        
        // Check old key that might be used
        if let oldGroupId = defaults.string(forKey: "activeGroupID") {
            print("   ⚠️ Found old activeGroupID = \(oldGroupId)")
        }
    }
    
    // MARK: - Load Saved Group
    public func loadSavedGroup() async {
        // Only check UserDefaults, no debug logging on every startup
        guard let savedGroupId = UserDefaults.standard.string(forKey: "currentFirebaseGroupId") else {
            // No group saved - this is normal for users not using group features
            AppLogger.main.debug("No Firebase group configured - skipping group load")
            
            // BUT - check if user is already a member of any groups
            await findUserGroups()
            return
        }
        
        AppLogger.main.info("Loading saved Firebase group: \(savedGroupId)")
        
        // Try to fetch the group from Firebase
        do {
            let groupDoc = try await db.collection("groups").document(savedGroupId).getDocument()
            
            guard groupDoc.exists, let data = groupDoc.data() else {
                AppLogger.main.warning("⚠️ Saved group \(savedGroupId) not found in Firebase - creating new personal group")
                UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
                currentGroup = nil
                
                // Auto-create a new personal group since the old one doesn't exist
                do {
                    try await createPersonalGroup()
                    AppLogger.main.info("✅ Created new personal group after old one was deleted")
                } catch {
                    AppLogger.main.error("❌ Failed to create new personal group: \(error)")
                }
                return
            }
            
            // Decode the group
            let group = FirestoreGroup(
                documentId: groupDoc.documentID,
                id: data["id"] as? String ?? "",
                name: data["name"] as? String ?? "",
                inviteCode: data["inviteCode"] as? String ?? "",
                createdBy: data["createdBy"] as? String ?? "",
                adminIds: data["adminIds"] as? [String] ?? [],
                memberIds: data["memberIds"] as? [String] ?? [],
                writePermissionIds: data["writePermissionIds"] as? [String] ?? [],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            currentGroup = group
            AppLogger.main.info("✅ Restored Firebase group: \(group.name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: group.id)
            
        } catch {
            AppLogger.main.error("Failed to load saved group: \(error)")
            UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
        }
    }
    
    // MARK: - Find User's Groups
    /// Find all groups where the current user is a member
    public func findUserGroups() async {
        guard let userId = try? await authService.getCurrentUserId() else { return }
        
        AppLogger.main.info("🔍 Searching for user's existing groups...")
        
        do {
            // Query for groups where user is in memberIds (with timeout)
            let queryTask = Task {
                try await db.collection("groups")
                    .whereField("memberIds", arrayContains: userId)
                    .getDocuments()
            }
            
            // Add timeout of 3 seconds for the query
            let snapshot = try await withThrowingTaskGroup(of: QuerySnapshot.self) { group in
                group.addTask { try await queryTask.value }
                group.addTask {
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 second timeout
                    throw AppError.requestTimeout
                }
                
                // Return first result (either snapshot or timeout error)
                guard let result = try await group.next() else {
                    throw AppError.requestTimeout
                }
                group.cancelAll()
                return result
            }
            
            if snapshot.documents.isEmpty {
                AppLogger.main.info("No existing groups found for user")
                return
            }
            
            AppLogger.main.info("Found \(snapshot.documents.count) group(s) for user")
            
            // Load the first group (since we only support one group at a time)
            if let groupDoc = snapshot.documents.first {
                let data = groupDoc.data()
                
                let group = FirestoreGroup(
                    documentId: groupDoc.documentID,
                    id: data["id"] as? String ?? "",
                    name: data["name"] as? String ?? "",
                    inviteCode: data["inviteCode"] as? String ?? "",
                    createdBy: data["createdBy"] as? String ?? "",
                    adminIds: data["adminIds"] as? [String] ?? [],
                    memberIds: data["memberIds"] as? [String] ?? [],
                    writePermissionIds: data["writePermissionIds"] as? [String] ?? [],
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                    trialStartDate: (data["trialStartDate"] as? Timestamp)?.dateValue(),
                    trialEndDate: (data["trialEndDate"] as? Timestamp)?.dateValue()
                )
                
                AppLogger.main.info("✅ Auto-loaded existing group: \(group.name)")
                currentGroup = group  // This will trigger didSet to save to UserDefaults
                
                // Start listening to this group
                startListeningToGroup(groupId: group.id)
            }
            
        } catch {
            AppLogger.main.error("Failed to find user groups: \(error)")
        }
    }
    
    // MARK: - Load Group by ID
    public func loadGroupById(_ groupId: String) async {
        print("📝 Loading group with ID: \(groupId)")
        
        do {
            let groupDoc = try await db.collection("groups").document(groupId).getDocument()
            
            guard let data = groupDoc.data() else {
                print("⚠️ Group not found in Firebase: \(groupId)")
                return
            }
            
            // Decode the group
            let group = FirestoreGroup(
                documentId: groupDoc.documentID,
                id: data["id"] as? String ?? "",
                name: data["name"] as? String ?? "",
                inviteCode: data["inviteCode"] as? String ?? "",
                createdBy: data["createdBy"] as? String ?? "",
                adminIds: data["adminIds"] as? [String] ?? [],
                memberIds: data["memberIds"] as? [String] ?? [],
                writePermissionIds: data["writePermissionIds"] as? [String] ?? [],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            currentGroup = group
            print("✅ Loaded group: \(group.name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: group.id)
            
        } catch {
            print("❌ Failed to load group: \(error)")
        }
    }
    
    // MARK: - Auto-create Personal Group
    /// Creates a personal group for a new user (single member)
    public func createPersonalGroup() async throws {
        guard let userId = try? await authService.getCurrentUserId() else { return }
        
        // Check if user already has a group
        if currentGroup != nil {
            AppLogger.main.info("User already has a group, skipping personal group creation")
            return
        }
        
        // Create a personal group with just this user
        let groupId = UUID().uuidString
        let inviteCode = generateInviteCode()
        
        // Get current trial dates from CloudTrialManager
        let trialManager = CloudTrialManager.shared
        let trialStart = trialManager.trialState?.startDate ?? Date()
        let trialEnd = trialManager.trialState?.expiryDate ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())
        
        let group = FirestoreGroup(
            id: groupId,
            name: "Personal Care Group",
            inviteCode: inviteCode,
            createdBy: userId,
            adminIds: [userId],
            memberIds: [userId],
            writePermissionIds: [userId],
            createdAt: Date(),
            updatedAt: Date(),
            trialStartDate: trialStart,
            trialEndDate: trialEnd
        )
        
        do {
            try await db.collection("groups").document(groupId).setData(group.dictionary)
            
            // Save invite code mapping
            try await db.collection("inviteCodes").document(inviteCode.uppercased()).setData([
                "groupId": groupId,
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            currentGroup = group
            AppLogger.main.info("✅ Personal group created for new user")
            
            // Also create in Core Data for UI display
            await createGroupInCoreData(group)
            
            // Start listening to this group
            startListeningToGroup(groupId: groupId)
            
        } catch {
            AppLogger.main.error("Failed to create personal group: \(error)")
        }
    }
    
    // Generate a unique invite code
    private func generateInviteCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in letters.randomElement()! })
    }
    
    // Helper to create group in Core Data for UI display
    private func createGroupInCoreData(_ firestoreGroup: FirestoreGroup) async {
        let deviceID = await DeviceCheckManager.shared.getDeviceIdentifier()
        let deviceUUID = UUID(uuidString: deviceID) ?? UUID()
        
        // Create CareGroup from FirestoreGroup with proper id initialization
        var careGroup = CareGroup(
            id: UUID(uuidString: firestoreGroup.id) ?? UUID(),
            name: firestoreGroup.name,
            adminUserID: deviceUUID,
            settings: GroupSettings.default
        )
        careGroup.inviteCode = firestoreGroup.inviteCode
        
        // Save to Core Data
        do {
            try await CoreDataManager.shared.saveGroup(careGroup)
            AppLogger.main.info("✅ Group saved to Core Data for UI display")
        } catch {
            AppLogger.main.error("Failed to save group to Core Data: \(error)")
        }
    }
    
    // MARK: - Create Group
    func createGroup(name: String, inviteCode: String) async throws -> FirestoreGroup {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure user is authenticated
        let userId = try await authService.getCurrentUserId()
        
        // DELETE OLD GROUP if exists (only one group at a time)
        // Only delete if user owns the group
        if let oldGroup = currentGroup, oldGroup.createdBy == userId {
            AppLogger.main.info("🗑️ Deleting old group: \(oldGroup.name)")
            try await deleteGroup(oldGroup.id)
        } else if let oldGroup = currentGroup {
            AppLogger.main.info("ℹ️ Leaving old group: \(oldGroup.name) (not owner)")
            // Just clear the local reference, don't delete from Firebase
            currentGroup = nil
        }
        
        // Create group document
        let groupId = UUID().uuidString
        
        // Get current trial dates from CloudTrialManager
        let trialManager = CloudTrialManager.shared
        let trialStart = trialManager.trialState?.startDate ?? Date()
        let trialEnd = trialManager.trialState?.expiryDate ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())
        
        let group = FirestoreGroup(
            id: groupId,
            name: name,
            inviteCode: inviteCode,
            createdBy: userId,
            adminIds: [userId],
            memberIds: [userId],
            writePermissionIds: [userId],
            createdAt: Date(),
            updatedAt: Date(),
            trialStartDate: trialStart,
            trialEndDate: trialEnd
        )
        
        do {
            // Save to Firestore
            try await db.collection("groups").document(groupId).setData(group.dictionary)
            
            // Also save the invite code mapping for easy lookup (always uppercase)
            try await db.collection("inviteCodes").document(inviteCode.uppercased()).setData([
                "groupId": groupId,
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            currentGroup = group
            print("\n🎯 GROUP CREATED AND SET:")
            print("   Name: \(group.name)")
            print("   ID: \(group.id)")
            print("   Admin IDs: \(group.adminIds)")
            print("   Write Permission IDs: \(group.writePermissionIds)")
            print("   Current group verification: \(currentGroup?.name ?? "NIL")")
            
            AppLogger.main.info("✅ Group created in Firebase: \(name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: groupId)
            
            // IMPORTANT: With group-centric architecture, data is already in group space
            // No need to sync from personal space anymore
            AppLogger.main.info("✅ Group created - all data will be stored in group space")
            
            // Double-check the group is set
            print("   Final check - currentGroup is set: \(currentGroup != nil)")
            print("   FirebaseGroupService.shared.currentGroup: \(FirebaseGroupService.shared.currentGroup?.name ?? "NIL")")
            
            return group
            
        } catch {
            AppLogger.main.error("❌ Failed to create group in Firebase: \(error)")
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Join Group
    func joinGroup(inviteCode: String, memberName: String) async throws -> FirestoreGroup {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure user is authenticated
        let userId = try await authService.getCurrentUserId()
        
        do {
            // Look up group ID from invite code (make it uppercase to match storage)
            let upperInviteCode = inviteCode.uppercased()
            AppLogger.main.info("🔍 Looking up invite code: \(upperInviteCode)")
            
            let inviteDoc = try await db.collection("inviteCodes").document(upperInviteCode).getDocument()
            
            guard let groupId = inviteDoc.data()?["groupId"] as? String else {
                AppLogger.main.error("❌ No group found for invite code: \(upperInviteCode)")
                throw GroupError.invalidInviteCode
            }
            
            // Get the group document
            let groupDoc = try await db.collection("groups").document(groupId).getDocument()
            
            guard let data = groupDoc.data() else {
                throw GroupError.groupNotFound
            }
            
            // Manually decode
            var group = FirestoreGroup(
                documentId: groupDoc.documentID,
                id: data["id"] as? String ?? "",
                name: data["name"] as? String ?? "",
                inviteCode: data["inviteCode"] as? String ?? "",
                createdBy: data["createdBy"] as? String ?? "",
                adminIds: data["adminIds"] as? [String] ?? [],
                memberIds: data["memberIds"] as? [String] ?? [],
                writePermissionIds: data["writePermissionIds"] as? [String] ?? [],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
            
            // Check if already a member
            if group.memberIds.contains(userId) {
                throw GroupError.alreadyMember
            }
            
            // Check member limit (3 members max)
            if group.memberIds.count >= 3 {
                throw GroupError.groupFull
            }
            
            // Add user to group (READ-ONLY access)
            group.memberIds.append(userId)
            // Members get read-only access - only admin has write permission
            
            // Update Firestore - add to memberIds only (not writePermissionIds)
            try await db.collection("groups").document(groupId).updateData([
                "memberIds": FieldValue.arrayUnion([userId]),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            // Save member info with read-only permissions
            let member = FirestoreMember(
                id: UUID().uuidString,
                userId: userId,
                groupId: groupId,
                name: memberName,
                displayName: nil,  // Primary user can set this later
                role: "member",
                permissions: "read",  // Members get read-only access
                isAccessEnabled: true,  // Enabled by default
                joinedAt: Date()
            )
            
            try await db.collection("groups").document(groupId)
                .collection("members").document(userId)
                .setData(member.dictionary)
            
            currentGroup = group
            AppLogger.main.info("✅ Joined group via Firebase: \(group.name)")
            
            // Sync trial period with group's admin trial
            if let trialStart = group.trialStartDate, let trialEnd = group.trialEndDate {
                AppLogger.main.info("📅 Inheriting trial period from group admin")
                AppLogger.main.info("   Trial ends: \(trialEnd)")
                
                // Update local subscription manager with group's trial dates
                await SubscriptionManager.shared.setTrialState(
                    startDate: trialStart,
                    endDate: trialEnd,
                    sessionsUsed: 0,
                    sessionsRemaining: 999
                )
            }
            
            // IMPORTANT: Don't start listening until AFTER the Firestore update completes
            // The listener requires the user to be in memberIds, which happens asynchronously
            // We'll start listening after a small delay to ensure Firestore has updated
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                await MainActor.run {
                    startListeningToGroup(groupId: groupId)
                }
            }
            
            // New caregivers joining won't have data - they're here to help manage the patient's medications
            // They will immediately see all existing medications through fetchAllMedications()
            // which pulls from both personal spaces and group references
            AppLogger.main.info("📊 New caregiver can now see all group medications")
            
            return group
            
        } catch {
            AppLogger.main.error("❌ Failed to join group: \(error)")
            syncError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Update Member Display Name
    func updateMemberDisplayName(groupId: String, memberId: String, displayName: String) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure current user is admin
        let userId = try await authService.getCurrentUserId()
        
        // Verify user is admin of the group
        guard let group = currentGroup, group.adminIds.contains(userId) else {
            throw GroupError.notAdmin
        }
        
        // Update member's display name
        try await db.collection("groups").document(groupId)
            .collection("members").document(memberId)
            .updateData([
                "displayName": displayName,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        
        AppLogger.main.info("✅ Member display name updated to: \(displayName)")
    }
    
    // MARK: - Toggle Member Access
    func toggleMemberAccess(groupId: String, memberId: String, isEnabled: Bool) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure current user is admin
        let userId = try await authService.getCurrentUserId()
        
        // Verify user is admin of the group
        guard let group = currentGroup, group.adminIds.contains(userId) else {
            throw GroupError.notAdmin
        }
        
        // Update member's access status
        try await db.collection("groups").document(groupId)
            .collection("members").document(memberId)
            .updateData([
                "isAccessEnabled": isEnabled,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        
        // If disabling access, also remove from write permissions
        if !isEnabled {
            try await db.collection("groups").document(groupId).updateData([
                "writePermissionIds": FieldValue.arrayRemove([memberId])
            ])
        } else {
            // Re-enable write permissions when access is restored
            try await db.collection("groups").document(groupId).updateData([
                "writePermissionIds": FieldValue.arrayUnion([memberId])
            ])
        }
        
        AppLogger.main.info("✅ Member access \(isEnabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Remove Member from Group
    func removeMember(groupId: String, memberId: String) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure current user is admin
        let userId = try await authService.getCurrentUserId()
        
        // Verify user is admin of the group
        guard let group = currentGroup, group.adminIds.contains(userId) else {
            throw GroupError.notAdmin
        }
        
        // Cannot remove the primary admin
        if memberId == group.createdBy {
            throw GroupError.cannotRemovePrimaryAdmin
        }
        
        AppLogger.main.info("🗑️ Removing member \(memberId) from group \(groupId)")
        
        // CRITICAL FIX: First get the current group data
        let groupRef = db.collection("groups").document(groupId)
        let groupDoc = try await groupRef.getDocument()
        
        guard let groupData = groupDoc.data() else {
            throw GroupError.groupNotFound
        }
        
        // Get current arrays
        var memberIds = groupData["memberIds"] as? [String] ?? []
        var adminIds = groupData["adminIds"] as? [String] ?? []
        var writePermissionIds = groupData["writePermissionIds"] as? [String] ?? []
        
        // Check if member is actually in the arrays before trying to remove
        let wasInMemberIds = memberIds.contains(memberId)
        let wasInAdminIds = adminIds.contains(memberId)
        let wasInWriteIds = writePermissionIds.contains(memberId)
        
        if !wasInMemberIds {
            AppLogger.main.warning("⚠️ Member \(memberId) not found in memberIds - may have already been removed")
        }
        
        // Remove the member from all arrays
        memberIds.removeAll { $0 == memberId }
        adminIds.removeAll { $0 == memberId }
        writePermissionIds.removeAll { $0 == memberId }
        
        // Update the group document with explicit arrays (not FieldValue.arrayRemove)
        // This ensures the member is completely removed
        try await groupRef.updateData([
            "memberIds": memberIds,
            "adminIds": adminIds,
            "writePermissionIds": writePermissionIds,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        AppLogger.main.info("✅ Member arrays updated successfully")
        AppLogger.main.info("   Was in memberIds: \(wasInMemberIds)")
        AppLogger.main.info("   Was in adminIds: \(wasInAdminIds)")
        AppLogger.main.info("   Was in writePermissionIds: \(wasInWriteIds)")
        
        // Delete member document (do this after transaction completes)
        do {
            try await db.collection("groups").document(groupId)
                .collection("members").document(memberId).delete()
            AppLogger.main.info("✅ Member document deleted")
        } catch {
            // Member doc might not exist, that's okay
            AppLogger.main.warning("Member document might not exist: \(error)")
        }
        
        // Clean up member's medication/supplement references
        // Delete individually to avoid batch Sendable issues
        
        // Delete member medication references
        let memberMedRefs = try await db.collection("groups").document(groupId)
            .collection("member_medications")
            .whereField("userId", isEqualTo: memberId)
            .getDocuments()
        
        for doc in memberMedRefs.documents {
            try await doc.reference.delete()
        }
        
        // Delete member supplement references
        let memberSupRefs = try await db.collection("groups").document(groupId)
            .collection("member_supplements")
            .whereField("userId", isEqualTo: memberId)
            .getDocuments()
        
        for doc in memberSupRefs.documents {
            try await doc.reference.delete()
        }
        
        // Delete member diet references
        let memberDietRefs = try await db.collection("groups").document(groupId)
            .collection("member_diets")
            .whereField("userId", isEqualTo: memberId)
            .getDocuments()
        
        for doc in memberDietRefs.documents {
            try await doc.reference.delete()
        }
        
        AppLogger.main.info("✅ Member completely removed from group \(groupId)")
        AppLogger.main.info("   Removed from memberIds, adminIds, writePermissionIds")
        AppLogger.main.info("   Deleted member document and all references")
    }
    
    // MARK: - Get Group Members
    func fetchGroupMembers(groupId: String) async throws -> [FirestoreMember] {
        let snapshot = try await db.collection("groups").document(groupId)
            .collection("members").getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            var member = FirestoreMember(
                id: data["id"] as? String ?? "",
                userId: data["userId"] as? String ?? "",
                groupId: data["groupId"] as? String ?? "",
                name: data["name"] as? String ?? "Unknown",
                displayName: data["displayName"] as? String,
                role: data["role"] as? String ?? "member",
                permissions: data["permissions"] as? String ?? "read",
                isAccessEnabled: data["isAccessEnabled"] as? Bool ?? true,
                joinedAt: (data["joinedAt"] as? Timestamp)?.dateValue() ?? Date(),
                lastActiveAt: (data["lastActiveAt"] as? Timestamp)?.dateValue()
            )
            member.documentId = doc.documentID
            return member
        }
    }
    
    // MARK: - Promote Member to Admin
    func promoteMemberToAdmin(groupId: String, memberId: String) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure current user is admin
        let userId = try await authService.getCurrentUserId()
        
        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        guard let groupData = groupDoc.data() else {
            throw GroupError.groupNotFound
        }
        
        let group = FirestoreGroup(
            documentId: groupDoc.documentID,
            id: groupData["id"] as? String ?? "",
            name: groupData["name"] as? String ?? "",
            inviteCode: groupData["inviteCode"] as? String ?? "",
            createdBy: groupData["createdBy"] as? String ?? "",
            adminIds: groupData["adminIds"] as? [String] ?? [],
            memberIds: groupData["memberIds"] as? [String] ?? [],
            writePermissionIds: groupData["writePermissionIds"] as? [String] ?? [],
            createdAt: (groupData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (groupData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
        
        guard group.adminIds.contains(userId) else {
            throw GroupError.notAdmin
        }
        
        // Update member permissions
        try await db.collection("groups").document(groupId).updateData([
            "adminIds": FieldValue.arrayUnion([memberId]),
            "writePermissionIds": FieldValue.arrayUnion([memberId]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Update member role
        try await db.collection("groups").document(groupId)
            .collection("members").document(memberId)
            .updateData([
                "role": "admin",
                "permissions": "write"
            ])
        
        AppLogger.main.info("✅ Member promoted to admin")
    }
    
    // MARK: - Save Shared Data
    func saveSharedData<T: Codable>(
        groupId: String,
        collection: String,
        documentId: String,
        data: T
    ) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure user has write permission
        let userId = try await authService.getCurrentUserId()
        
        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        guard let groupData = groupDoc.data() else {
            throw GroupError.groupNotFound
        }
        
        let group = FirestoreGroup(
            documentId: groupDoc.documentID,
            id: groupData["id"] as? String ?? "",
            name: groupData["name"] as? String ?? "",
            inviteCode: groupData["inviteCode"] as? String ?? "",
            createdBy: groupData["createdBy"] as? String ?? "",
            adminIds: groupData["adminIds"] as? [String] ?? [],
            memberIds: groupData["memberIds"] as? [String] ?? [],
            writePermissionIds: groupData["writePermissionIds"] as? [String] ?? [],
            createdAt: (groupData["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (groupData["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
        
        guard group.writePermissionIds.contains(userId) else {
            throw GroupError.noWritePermission
        }
        
        // Save to sharedData collection
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        
        // Create the dictionary with metadata in a single step to avoid mutation
        let jsonBase = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]
        let finalDict: [String: Any] = jsonBase.merging([
            "lastUpdatedBy": userId,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { (_, new) in new }
        
        // Wrap in Task to handle Sendable requirement
        try await Task { @MainActor in
            try await db.collection("sharedData").document(groupId)
                .collection(collection).document(documentId)
                .setData(finalDict, merge: true)
        }.value
        
        AppLogger.main.info("✅ Shared data saved to Firebase")
    }
    
    // MARK: - Fetch Shared Data
    func fetchSharedData(groupId: String, collection: String) async throws -> [[String: Any]] {
        let snapshot = try await db.collection("sharedData").document(groupId)
            .collection(collection).getDocuments()
        
        return snapshot.documents.map { $0.data() }
    }
    
    // MARK: - Real-time Listener
    private func startListeningToGroup(groupId: String) {
        // Remove existing listener if any
        stopListeningToGroup(groupId: groupId)
        
        // Listen to group changes
        let listener = db.collection("groups").document(groupId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("Group listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists, let data = snapshot.data() else {
                    // Group document doesn't exist anymore
                    if snapshot != nil && !snapshot!.exists {
                        AppLogger.main.warning("⚠️ Group document deleted from Firebase")
                        Task { @MainActor in
                            self.currentGroup = nil
                            UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
                            // Try to create a new personal group
                            try? await self.createPersonalGroup()
                        }
                    }
                    return
                }
                
                // Manually decode the group
                let group = FirestoreGroup(
                    documentId: snapshot.documentID,
                    id: data["id"] as? String ?? "",
                    name: data["name"] as? String ?? "",
                    inviteCode: data["inviteCode"] as? String ?? "",
                    createdBy: data["createdBy"] as? String ?? "",
                    adminIds: data["adminIds"] as? [String] ?? [],
                    memberIds: data["memberIds"] as? [String] ?? [],
                    writePermissionIds: data["writePermissionIds"] as? [String] ?? [],
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
                
                Task { @MainActor in
                    self.currentGroup = group
                    AppLogger.main.info("📱 Group updated from Firebase")
                }
            }
        
        groupListeners[groupId] = listener
        
        // Also listen to shared data changes
        listenToSharedData(groupId: groupId)
    }
    
    private func listenToSharedData(groupId: String) {
        // Listen to medications
        let medListener = db.collection("sharedData").document(groupId)
            .collection("medications")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.main.error("Medication listener error: \(error)")
                    return
                }
                
                AppLogger.main.info("📱 Medications updated: \(snapshot?.documents.count ?? 0) items")
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .groupDataDidChange,
                    object: nil,
                    userInfo: ["groupId": groupId, "collection": "medications"]
                )
            }
        
        groupListeners["\(groupId)_medications"] = medListener
        
        // Listen to supplements
        let supListener = db.collection("sharedData").document(groupId)
            .collection("supplements")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.main.error("Supplement listener error: \(error)")
                    return
                }
                
                AppLogger.main.info("📱 Supplements updated: \(snapshot?.documents.count ?? 0) items")
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .groupDataDidChange,
                    object: nil,
                    userInfo: ["groupId": groupId, "collection": "supplements"]
                )
            }
        
        groupListeners["\(groupId)_supplements"] = supListener
    }
    
    private func stopListeningToGroup(groupId: String) {
        groupListeners[groupId]?.remove()
        groupListeners["\(groupId)_medications"]?.remove()
        groupListeners["\(groupId)_supplements"]?.remove()
        
        groupListeners.removeValue(forKey: groupId)
        groupListeners.removeValue(forKey: "\(groupId)_medications")
        groupListeners.removeValue(forKey: "\(groupId)_supplements")
    }
    
    // MARK: - Sync All Existing Data to Group
    func syncAllExistingDataToGroup() async {
        guard let group = currentGroup,
              let userId = try? await authService.getCurrentUserId() else {
            AppLogger.main.warning("⚠️ Cannot sync - no active group or user")
            return
        }
        
        AppLogger.main.info("🔄 Syncing all existing data to group: \(group.name)")
        
        // Get reference to user's personal data
        let userRef = db.collection("users").document(userId)
        
        do {
            // Sync medications
            let medSnapshot = try await userRef.collection("medications").getDocuments()
            for doc in medSnapshot.documents {
                let medId = doc.documentID
                let reference = [
                    "userId": userId,
                    "medicationId": medId,
                    "personalDataPath": "users/\(userId)/medications/\(medId)",
                    "updatedAt": FieldValue.serverTimestamp()
                ] as [String : Any]
                
                try await db.collection("groups").document(group.id)
                    .collection("member_medications").document("\(userId)_\(medId)")
                    .setData(reference)
            }
            AppLogger.main.info("✅ Synced \(medSnapshot.documents.count) medications to group")
            
            // Sync supplements
            let supSnapshot = try await userRef.collection("supplements").getDocuments()
            for doc in supSnapshot.documents {
                let supId = doc.documentID
                let reference = [
                    "userId": userId,
                    "supplementId": supId,
                    "personalDataPath": "users/\(userId)/supplements/\(supId)",
                    "updatedAt": FieldValue.serverTimestamp()
                ] as [String : Any]
                
                try await db.collection("groups").document(group.id)
                    .collection("member_supplements").document("\(userId)_\(supId)")
                    .setData(reference)
            }
            AppLogger.main.info("✅ Synced \(supSnapshot.documents.count) supplements to group")
            
            // Sync diets
            let dietSnapshot = try await userRef.collection("diets").getDocuments()
            for doc in dietSnapshot.documents {
                let dietId = doc.documentID
                let reference = [
                    "userId": userId,
                    "dietId": dietId,
                    "personalDataPath": "users/\(userId)/diets/\(dietId)",
                    "updatedAt": FieldValue.serverTimestamp()
                ] as [String : Any]
                
                try await db.collection("groups").document(group.id)
                    .collection("member_diets").document("\(userId)_\(dietId)")
                    .setData(reference)
            }
            AppLogger.main.info("✅ Synced \(dietSnapshot.documents.count) diet items to group")
            
        } catch {
            AppLogger.main.error("❌ Failed to sync existing data to group: \(error)")
        }
    }
    
    // MARK: - Delete Group
    /// Delete a group and all its data
    private func deleteGroup(_ groupId: String) async throws {
        // Stop listening to the group
        stopListeningToGroup(groupId: groupId)
        
        // Delete all subcollections
        let groupRef = db.collection("groups").document(groupId)
        
        // Delete medications
        let medications = try await groupRef.collection("medications").getDocuments()
        for doc in medications.documents {
            try await doc.reference.delete()
        }
        
        // Delete supplements
        let supplements = try await groupRef.collection("supplements").getDocuments()
        for doc in supplements.documents {
            try await doc.reference.delete()
        }
        
        // Delete diets
        let diets = try await groupRef.collection("diets").getDocuments()
        for doc in diets.documents {
            try await doc.reference.delete()
        }
        
        // Delete members
        let members = try await groupRef.collection("members").getDocuments()
        for doc in members.documents {
            try await doc.reference.delete()
        }
        
        // Delete the old member_medications, member_supplements, member_diets (from old architecture)
        let memberMeds = try await groupRef.collection("member_medications").getDocuments()
        for doc in memberMeds.documents {
            try await doc.reference.delete()
        }
        
        let memberSups = try await groupRef.collection("member_supplements").getDocuments()
        for doc in memberSups.documents {
            try await doc.reference.delete()
        }
        
        let memberDiets = try await groupRef.collection("member_diets").getDocuments()
        for doc in memberDiets.documents {
            try await doc.reference.delete()
        }
        
        // Finally, delete the group document itself
        try await groupRef.delete()
        
        // Remove invite code
        if let inviteCode = currentGroup?.inviteCode {
            try? await db.collection("inviteCodes").document(inviteCode.uppercased()).delete()
        }
        
        AppLogger.main.info("✅ Deleted group: \(groupId)")
    }
    
    // MARK: - Cleanup
    func cleanup() {
        groupListeners.forEach { $0.value.remove() }
        groupListeners.removeAll()
    }
    
    deinit {
        // Cleanup is handled by the caller when needed
        // Cannot call @MainActor methods from deinit
    }
}

// MARK: - Error Types
enum GroupError: LocalizedError {
    case invalidInviteCode
    case groupNotFound
    case alreadyMember
    case groupFull
    case notAdmin
    case noWritePermission
    case cannotRemovePrimaryAdmin
    
    var errorDescription: String? {
        switch self {
        case .invalidInviteCode:
            return "Invalid invite code"
        case .groupNotFound:
            return "Group not found"
        case .alreadyMember:
            return "You are already a member of this group"
        case .groupFull:
            return "This group is full (maximum 3 members)"
        case .notAdmin:
            return "Only admins can perform this action"
        case .noWritePermission:
            return "You don't have permission to modify this data"
        case .cannotRemovePrimaryAdmin:
            return "Cannot remove the primary admin from the group"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let firebaseGroupDidChange = Notification.Name("firebaseGroupDidChange")
}