//
//  FirebaseGroupService.swift
//  HealthGuide
//
//  Manages Firebase Firestore group operations for cross-Apple ID sharing
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Notification Names
extension Notification.Name {
    static let firebaseGroupDidChange = Notification.Name("firebaseGroupDidChange")
    static let memberAccessRevoked = Notification.Name("memberAccessRevoked")
    static let firebasePermissionDenied = Notification.Name("firebasePermissionDenied")
    static let firebaseGroupMembersDidChange = Notification.Name("firebaseGroupMembersDidChange")
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
}

@available(iOS 18.0, *)
@MainActor
final class FirebaseGroupService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseGroupService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let authService = FirebaseAuthService.shared
    private var groupListeners: [String: ListenerRegistration] = [:]
    private var accessListener: ListenerRegistration?
    private var memberStatusListener: ListenerRegistration?
    
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
    @Published var pendingJoinRequests: [PendingJoinRequest] = []
    
    // Listener for join requests
    private var joinRequestsListener: ListenerRegistration?
    
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
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                trialStartDate: (data["trialStartDate"] as? Timestamp)?.dateValue(),
                trialEndDate: (data["trialEndDate"] as? Timestamp)?.dateValue(),
                hasActiveSubscription: data["hasActiveSubscription"] as? Bool ?? false
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
                    trialEndDate: (data["trialEndDate"] as? Timestamp)?.dateValue(),
                    hasActiveSubscription: data["hasActiveSubscription"] as? Bool ?? false
                )
                
                AppLogger.main.info("✅ Auto-loaded existing group: \(group.name)")
                currentGroup = group  // This will trigger didSet to save to UserDefaults
                
                // Migration: Create admin member document if missing
                if group.adminIds.contains(userId) {
                    Task {
                        await createAdminMemberIfMissing(group: group, userId: userId)
                    }
                }
                
                // Start listening to this group
                startListeningToGroup(groupId: group.id)
                
                // Start monitoring member status for access revocation (for non-admin members)
                if !group.adminIds.contains(userId) {
                    startMemberStatusMonitoring(groupId: group.id, userId: userId)
                }
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
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                trialStartDate: (data["trialStartDate"] as? Timestamp)?.dateValue(),
                trialEndDate: (data["trialEndDate"] as? Timestamp)?.dateValue(),
                hasActiveSubscription: data["hasActiveSubscription"] as? Bool ?? false
            )
            
            currentGroup = group
            print("✅ Loaded group: \(group.name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: group.id)
            
        } catch {
            print("❌ Failed to load group: \(error)")
        }
    }
    
    // MARK: - Migration Helper
    /// Create admin member document if it doesn't exist (for migration of existing groups)
    private func createAdminMemberIfMissing(group: FirestoreGroup, userId: String) async {
        do {
            let memberDoc = try await db.collection("groups").document(group.id)
                .collection("members").document(userId).getDocument()
            
            if !memberDoc.exists {
                AppLogger.main.info("📝 Creating missing admin member document for migration")
                
                let adminMember = FirestoreMember(
                    id: UUID().uuidString,
                    userId: userId,
                    groupId: group.id,
                    name: UIDevice.current.name,
                    displayName: "Group Admin",
                    role: "admin",
                    permissions: "write",
                    isAccessEnabled: true,
                    joinedAt: group.createdAt
                )
                
                try await db.collection("groups").document(group.id)
                    .collection("members").document(userId)
                    .setData(adminMember.dictionary)
                
                AppLogger.main.info("✅ Admin member document created for group: \(group.name)")
            }
        } catch {
            AppLogger.main.error("Failed to create admin member document: \(error)")
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
            trialEndDate: trialEnd,
            hasActiveSubscription: false  // Initially false, set to true when user subscribes
        )
        
        do {
            try await db.collection("groups").document(groupId).setData(group.dictionary)
            
            // Save invite code mapping
            try await db.collection("inviteCodes").document(inviteCode.uppercased()).setData([
                "groupId": groupId,
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            currentGroup = group
            
            // CRITICAL: Create admin member document
            let adminMember = FirestoreMember(
                id: UUID().uuidString,
                userId: userId,
                groupId: groupId,
                name: UIDevice.current.name,
                displayName: "Group Admin",
                role: "admin",
                permissions: "write",
                isAccessEnabled: true,
                joinedAt: Date()
            )
            
            try await db.collection("groups").document(groupId)
                .collection("members").document(userId)
                .setData(adminMember.dictionary)
            
            AppLogger.main.info("✅ Personal group created for new user with admin member document")
            
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
    
    // MARK: - Helper Methods for Group Management
    
    // Update group subscription status when payment is made
    @MainActor
    func updateGroupSubscriptionStatus(_ hasActiveSubscription: Bool) async throws {
        guard let group = currentGroup else {
            throw AppError.groupNotSet
        }
        
        AppLogger.main.info("💳 Updating subscription status for group \(group.id): \(hasActiveSubscription)")
        
        try await db.collection("groups").document(group.id).updateData([
            "hasActiveSubscription": hasActiveSubscription,
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Update the local currentGroup to reflect the new status
        currentGroup?.hasActiveSubscription = hasActiveSubscription
        
        AppLogger.main.info("✅ Group subscription status updated to: \(hasActiveSubscription)")
        
        // Post notification to update UI
        NotificationCenter.default.post(
            name: .subscriptionStatusChanged,
            object: nil,
            userInfo: ["hasActiveSubscription": hasActiveSubscription]
        )
    }
    
    // Calculate remaining trial days for the admin's group
    private func calculateAdminTrialDaysRemaining(group: FirestoreGroup) -> Int {
        // If group has trial end date, calculate days remaining
        if let trialEnd = group.trialEndDate {
            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
            return max(0, daysRemaining)
        }
        
        // Fallback: Check CloudTrialManager for current trial state
        if let trialState = CloudTrialManager.shared.trialState {
            let daysUsed = trialState.daysUsed
            return max(0, 14 - daysUsed)
        }
        
        // Default: assume no trial days remaining
        return 0
    }
    
    // Check if user is eligible to create a group (enforces cooldown)
    func checkTransitionEligibility(userId: String) async throws -> Bool {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        // If user document exists, check cooldown fields
        if userDoc.exists, let data = userDoc.data() {
            // CRITICAL: Check new cooldown fields that match Firestore rules
            let canCreateGroup = data["canCreateGroup"] as? Bool ?? true
            let cooldownEndDate = (data["cooldownEndDate"] as? Timestamp)?.dateValue()
            let currentRole = data["currentRole"] as? String
            
            // If explicitly set to false, check cooldown
            if !canCreateGroup {
                if let cooldownEnd = cooldownEndDate {
                    if Date() < cooldownEnd {
                        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: cooldownEnd).day ?? 0
                        AppLogger.main.warning("❌ User in cooldown period. Must wait \(daysRemaining) more days")
                        AppLogger.main.warning("   Current role: \(currentRole ?? "unknown")")
                        AppLogger.main.warning("   Cooldown ends: \(cooldownEnd)")
                        return false
                    } else {
                        // Cooldown expired, update user document
                        try await db.collection("users").document(userId).updateData([
                            "canCreateGroup": true,
                            "updatedAt": FieldValue.serverTimestamp()
                        ])
                        AppLogger.main.info("✅ Cooldown expired, user can now create groups")
                        return true
                    }
                } else {
                    // No cooldown date but canCreateGroup is false - shouldn't happen
                    AppLogger.main.warning("⚠️ User has canCreateGroup=false but no cooldownEndDate")
                    return false
                }
            }
            
            // Also check legacy transition limits for backwards compatibility
            let transitionCount = data["transitionCount"] as? Int ?? 0
            if transitionCount >= 3 {
                AppLogger.main.warning("❌ User has reached maximum transitions: \(transitionCount)")
                return false
            }
            
            return true
        }
        
        // No user document = new user, they can create a group
        // This is fine because they haven't been a member yet
        AppLogger.main.info("✅ New user (no document), allowed to create group")
        return true
    }
    
    // Delete a group and all its data
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
        
        // Delete the group document
        try await db.collection("groups").document(groupId).delete()
        
        // Delete invite code mapping
        if let inviteCode = currentGroup?.inviteCode {
            try await db.collection("inviteCodes").document(inviteCode.uppercased()).delete()
        }
        
        AppLogger.main.info("✅ Group deleted: \(groupId)")
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
        
        // CRITICAL: Check if user is eligible to create a group (30-day cooldown after being a member)
        let isEligible = try await checkTransitionEligibility(userId: userId)
        if !isEligible {
            AppLogger.main.error("❌ User not eligible to create group due to cooldown period")
            throw GroupError.transitionCooldown
        }
        
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
            trialEndDate: trialEnd,
            hasActiveSubscription: false  // Initially false, set to true when user subscribes
        )
        
        do {
            // Save to Firestore
            try await db.collection("groups").document(groupId).setData(group.dictionary)
            
            // Also save the invite code mapping for easy lookup (always uppercase)
            try await db.collection("inviteCodes").document(inviteCode.uppercased()).setData([
                "groupId": groupId,
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            // Create member document for the admin/creator
            let adminMember = FirestoreMember(
                id: UUID().uuidString,
                userId: userId,
                groupId: groupId,
                name: UIDevice.current.name,
                displayName: "Group Admin",
                role: "admin",
                permissions: "write",
                isAccessEnabled: true,
                joinedAt: Date()
            )
            
            try await db.collection("groups").document(groupId)
                .collection("members").document(userId)
                .setData(adminMember.dictionary)
            
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
    
    // MARK: - Get Group By Invite Code
    func getGroupByInviteCode(_ inviteCode: String) async throws -> FirestoreGroup {
        let upperInviteCode = inviteCode.uppercased()
        
        // Look up group ID from invite code
        let inviteDoc = try await db.collection("inviteCodes").document(upperInviteCode).getDocument()
        
        guard let groupId = inviteDoc.data()?["groupId"] as? String else {
            throw GroupError.invalidInviteCode
        }
        
        // Get the group document
        let groupDoc = try await db.collection("groups").document(groupId).getDocument()
        
        guard let data = groupDoc.data() else {
            throw GroupError.groupNotFound
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
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            trialStartDate: (data["trialStartDate"] as? Timestamp)?.dateValue(),
            trialEndDate: (data["trialEndDate"] as? Timestamp)?.dateValue()
        )
        
        return group
    }
    
    // MARK: - Join Group (Creates Join Request)
    func joinGroup(inviteCode: String, memberName: String) async throws -> String {
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
            
            // Parse group data to check status
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
                trialEndDate: (data["trialEndDate"] as? Timestamp)?.dateValue(),
                hasActiveSubscription: data["hasActiveSubscription"] as? Bool ?? false
            )
            
            // Check if already a member
            if group.memberIds.contains(userId) {
                throw GroupError.alreadyMember
            }
            
            // Check member limit (2 non-admin members max)
            // Count only non-admin members
            let nonAdminMembers = group.memberIds.filter { !group.adminIds.contains($0) }
            if nonAdminMembers.count >= 2 {
                throw GroupError.groupFull
            }
            
            // Check if there's already a pending request from this user
            let existingRequests = try await db.collection("joinRequests")
                .whereField("userId", isEqualTo: userId)
                .whereField("groupId", isEqualTo: groupId)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            
            if !existingRequests.documents.isEmpty {
                AppLogger.main.info("⏳ Join request already pending for this group")
                return "pending" // Request already exists
            }
            
            // Create a join request instead of directly joining
            let requestId = UUID().uuidString
            let joinRequest: [String: Any] = [
                "id": requestId,
                "userId": userId,
                "userName": memberName,
                "groupId": groupId,
                "groupName": group.name,
                "requestedAt": FieldValue.serverTimestamp(),
                "status": "pending",
                "adminId": group.createdBy // Admin who will approve
            ]
            
            // Create the join request
            try await db.collection("joinRequests").document(requestId).setData(joinRequest)
            
            // Also add to group's joinRequests subcollection for easier querying
            try await db.collection("groups").document(groupId)
                .collection("joinRequests").document(requestId)
                .setData(joinRequest)
            
            AppLogger.main.info("📨 Join request created - waiting for admin approval")
            
            // TODO: Send push notification to admin
            // This will be implemented when push notifications are set up
            
            return "pending" // Return status indicating request is pending
            
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
        
        // Update member's access status in subcollection
        try await db.collection("groups").document(groupId)
            .collection("members").document(memberId)
            .updateData([
                "isAccessEnabled": isEnabled,
                "updatedAt": FieldValue.serverTimestamp()
            ])
        
        if !isEnabled {
            // DISABLE: Remove from arrays using explicit array manipulation (more reliable)
            let groupDoc = try await db.collection("groups").document(groupId).getDocument()
            guard let data = groupDoc.data() else {
                AppLogger.main.error("❌ Could not get group data to toggle access")
                return
            }
            
            var memberIds = data["memberIds"] as? [String] ?? []
            var writePermissionIds = data["writePermissionIds"] as? [String] ?? []
            
            // Remove the member from arrays
            let wasInMemberIds = memberIds.contains(memberId)
            memberIds.removeAll { $0 == memberId }
            writePermissionIds.removeAll { $0 == memberId }
            
            // Update with explicit arrays and force listener trigger
            try await db.collection("groups").document(groupId).updateData([
                "memberIds": memberIds,
                "writePermissionIds": writePermissionIds,
                "updatedAt": FieldValue.serverTimestamp(),
                "lastMemberChange": FieldValue.serverTimestamp() // Force listener to fire
            ])
            
            AppLogger.main.info("🚫 Member access DISABLED - removed from group: \(memberId)")
            AppLogger.main.info("   Was in memberIds: \(wasInMemberIds)")
            AppLogger.main.info("   Remaining memberIds: \(memberIds)")
            
            // Don't post notification here - the member's own listener will detect removal
            // and handle it appropriately
            AppLogger.main.info("🔔 Member will be notified via their group listener")
        } else {
            // ENABLE: Add back to memberIds (but NOT writePermissionIds - they remain read-only)
            try await db.collection("groups").document(groupId).updateData([
                "memberIds": FieldValue.arrayUnion([memberId]),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            AppLogger.main.info("✅ Member access ENABLED - added back to group: \(memberId)")
        }
        
        // Post notification to refresh member lists in UI
        NotificationCenter.default.post(
            name: .firebaseGroupMembersDidChange,
            object: nil,
            userInfo: ["groupId": groupId]
        )
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
        // Add lastMemberChange timestamp to force listener updates
        try await groupRef.updateData([
            "memberIds": memberIds,
            "adminIds": adminIds,
            "writePermissionIds": writePermissionIds,
            "updatedAt": FieldValue.serverTimestamp(),
            "lastMemberChange": FieldValue.serverTimestamp() // Force listener refresh
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
        
        // Post notification to refresh member lists in UI
        NotificationCenter.default.post(
            name: .firebaseGroupMembersDidChange,
            object: nil,
            userInfo: ["groupId": groupId]
        )
        
        // CRITICAL: Update user document with cooldown when member is removed
        // Calculate cooldown based on admin's remaining trial days
        let adminTrialDaysRemaining = calculateAdminTrialDaysRemaining(group: group)
        let cooldownDays = max(1, 30 - adminTrialDaysRemaining) // At least 1 day cooldown
        let cooldownEndDate = Calendar.current.date(byAdding: .day, value: cooldownDays, to: Date())!
        
        // Update user document to enforce cooldown
        try await db.collection("users").document(memberId).setData([
            "currentRole": "removed",
            "canCreateGroup": false, // Cannot create group during cooldown
            "cooldownEndDate": Timestamp(date: cooldownEndDate),
            "removedFromGroupAt": FieldValue.serverTimestamp(),
            "removedFromGroupId": groupId,
            "adminTrialDaysRemainingAtRemoval": adminTrialDaysRemaining,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        AppLogger.main.info("📅 Member cooldown set until: \(cooldownEndDate)")
        AppLogger.main.info("   Admin trial days remaining: \(adminTrialDaysRemaining)")
        AppLogger.main.info("   Cooldown days: \(cooldownDays)")
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
    
    /// Periodically check if member still has access (backup to real-time listener)
    private var accessCheckTimer: Timer?
    
    /// Monitor member status for access revocation
    private func startMemberStatusMonitoring(groupId: String, userId: String) {
        AppLogger.main.info("👁️ Starting member status monitoring for user: \(userId) in group: \(groupId)")
        
        // Stop any existing listener
        memberStatusListener?.remove()
        accessCheckTimer?.invalidate()
        
        // Start periodic check as backup (every 5 seconds for immediate detection)
        accessCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                AppLogger.main.debug("⏱️ Running periodic membership check...")
                await self?.checkMemberAccess(groupId: groupId, userId: userId)
            }
        }
        
        // Listen to the group document for memberIds changes with metadata changes for faster updates
        memberStatusListener = db.collection("groups").document(groupId)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("❌ Error monitoring member status: \(error)")
                    // Check if it's a permission error (code 7)
                    if (error as NSError).code == 7 {
                        AppLogger.main.warning("🚫 Permission denied - triggering access revocation")
                        Task { @MainActor in
                            self.handleAccessRevoked()
                        }
                    }
                    return
                }
                
                guard let data = snapshot?.data(),
                      let memberIds = data["memberIds"] as? [String] else {
                    AppLogger.main.warning("⚠️ No member data in group snapshot")
                    return
                }
                
                AppLogger.main.info("🔄 Member status listener update - memberIds: \(memberIds)")
                
                // Check if current user is still in memberIds
                if !memberIds.contains(userId) {
                    AppLogger.main.warning("🚫 USER REMOVED FROM GROUP - no longer in memberIds")
                    AppLogger.main.warning("   User ID: \(userId)")
                    AppLogger.main.warning("   Group memberIds: \(memberIds)")
                    
                    Task { @MainActor in
                        // User has been removed from the group
                        self.handleAccessRevoked()
                    }
                }
            }
    }
    
    /// Periodically check member access (backup check)
    @MainActor
    private func checkMemberAccess(groupId: String, userId: String) async {
        do {
            let groupDoc = try await db.collection("groups").document(groupId).getDocument()
            
            guard let data = groupDoc.data(),
                  let memberIds = data["memberIds"] as? [String] else {
                AppLogger.main.warning("⚠️ Could not verify member access")
                return
            }
            
            let isMember = memberIds.contains(userId)
            AppLogger.main.debug("   Periodic check - User \(userId) is member: \(isMember)")
            
            if !isMember {
                AppLogger.main.warning("🚫 PERIODIC CHECK: User removed from group!")
                AppLogger.main.warning("   User ID: \(userId)")
                AppLogger.main.warning("   Current memberIds: \(memberIds)")
                handleAccessRevoked()
            }
        } catch {
            AppLogger.main.error("❌ Error checking member access: \(error)")
            // If permission denied (code 7), handle as revocation
            if (error as NSError).code == 7 {
                AppLogger.main.warning("🚫 Permission denied during periodic check - triggering revocation")
                handleAccessRevoked()
            }
        }
    }
    
    /// Handle when a member's access is revoked
    @MainActor
    private func handleAccessRevoked() {
        AppLogger.main.info("🔒 Handling access revocation...")
        
        // Stop all listeners and timers
        memberStatusListener?.remove()
        memberStatusListener = nil
        accessCheckTimer?.invalidate()
        accessCheckTimer = nil
        
        // Clear current group
        currentGroup = nil
        
        // Stop all Firebase services
        Task {
            await FirebaseServiceManager.shared.stopAllListeners()
        }
        
        // Clear cached data from UserDefaults
        UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
        UserDefaults.standard.synchronize()
        AppLogger.main.debug("Cleared Firebase group from UserDefaults")
        
        // Post notification to show blocking modal
        let userId = Auth.auth().currentUser?.uid ?? ""
        NotificationCenter.default.post(
            name: .memberAccessRevoked,
            object: nil,
            userInfo: [
                "memberId": userId,  // Include the member's ID so ContentView knows it's for this user
                "message": "Your access to this group has been revoked by the admin."
            ]
        )
        
        AppLogger.main.info("✅ Access revocation handled - user must rejoin or create new group")
    }
    
    // MARK: - Manual Access Check
    
    /// Manually check if user still has access to current group
    @MainActor
    public func manualAccessCheck() async {
        guard let group = currentGroup,
              let userId = Auth.auth().currentUser?.uid else {
            AppLogger.main.info("ℹ️ No group or user to check")
            return
        }
        
        AppLogger.main.info("🔍 MANUAL ACCESS CHECK initiated by user")
        
        do {
            let groupDoc = try await db.collection("groups").document(group.id).getDocument()
            
            guard let data = groupDoc.data(),
                  let memberIds = data["memberIds"] as? [String] else {
                AppLogger.main.warning("⚠️ Could not get group data for manual check")
                return
            }
            
            let isMember = memberIds.contains(userId)
            AppLogger.main.info("📊 Manual check result:")
            AppLogger.main.info("   User ID: \(userId)")
            AppLogger.main.info("   Group memberIds: \(memberIds)")
            AppLogger.main.info("   Is member: \(isMember)")
            
            if !isMember {
                AppLogger.main.warning("🚫 MANUAL CHECK: User not in group - triggering revocation!")
                handleAccessRevoked()
            } else {
                AppLogger.main.info("✅ Manual check passed - user still has access")
            }
        } catch {
            AppLogger.main.error("❌ Manual access check failed: \(error)")
            // If permission denied, treat as revocation
            if (error as NSError).code == 7 {
                AppLogger.main.warning("🚫 Permission denied in manual check")
                handleAccessRevoked()
            }
        }
    }
    
    // MARK: - Join Request Management
    
    /// Get pending join requests for the current group (admin only)
    @MainActor
    func getPendingJoinRequests() async throws -> [(id: String, userName: String, userId: String, requestedAt: Date)] {
        guard let group = currentGroup else {
            throw AppError.groupNotSet
        }
        
        guard let userId = try? authService.getCurrentUserIdSync(),
              group.adminIds.contains(userId) else {
            throw GroupError.notAdmin
        }
        
        let snapshot = try await db.collection("joinRequests")
            .whereField("groupId", isEqualTo: group.id)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let userName = data["userName"] as? String,
                  let userId = data["userId"] as? String,
                  let timestamp = data["requestedAt"] as? Timestamp else {
                return nil
            }
            return (id: doc.documentID, userName: userName, userId: userId, requestedAt: timestamp.dateValue())
        }
    }
    
    /// Approve a join request (admin only)
    @MainActor
    func approveJoinRequest(_ requestId: String) async throws {
        guard let group = currentGroup else {
            throw AppError.groupNotSet
        }
        
        guard let adminId = try? authService.getCurrentUserIdSync(),
              group.adminIds.contains(adminId) else {
            throw GroupError.notAdmin
        }
        
        // Get the join request
        let requestDoc = try await db.collection("joinRequests").document(requestId).getDocument()
        guard let data = requestDoc.data(),
              let userId = data["userId"] as? String,
              let userName = data["userName"] as? String,
              let groupId = data["groupId"] as? String else {
            throw AppError.internalError("Invalid join request data")
        }
        
        // Verify this request is for the admin's group
        guard groupId == group.id else {
            throw AppError.internalError("Request is for a different group")
        }
        
        // CRITICAL: Check member limit before approving (2 non-admin members max)
        let nonAdminMembers = group.memberIds.filter { !group.adminIds.contains($0) }
        if nonAdminMembers.count >= 2 {
            throw GroupError.groupFull
        }
        
        // Add member to group
        try await db.collection("groups").document(groupId).updateData([
            "memberIds": FieldValue.arrayUnion([userId]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Create member document
        let member = FirestoreMember(
            id: UUID().uuidString,
            userId: userId,
            groupId: groupId,
            name: userName,
            displayName: nil,
            role: "member",
            permissions: "read",
            isAccessEnabled: true,
            joinedAt: Date()
        )
        
        try await db.collection("groups").document(groupId)
            .collection("members").document(userId)
            .setData(member.dictionary)
        
        // Update join request status
        try await db.collection("joinRequests").document(requestId).updateData([
            "status": "approved",
            "approvedBy": adminId,
            "approvedAt": FieldValue.serverTimestamp()
        ])
        
        // CRITICAL: Create/update user document to prevent immediate group creation
        // Calculate remaining trial days from admin's perspective
        let adminTrialDaysRemaining = calculateAdminTrialDaysRemaining(group: group)
        let cooldownDays = max(1, 30 - adminTrialDaysRemaining) // At least 1 day cooldown
        let cooldownEndDate = Calendar.current.date(byAdding: .day, value: cooldownDays, to: Date())!
        
        // Create or update user document with member state
        try await db.collection("users").document(userId).setData([
            "userId": userId,
            "currentRole": "member",
            "canCreateGroup": false, // Members cannot create groups immediately
            "cooldownEndDate": Timestamp(date: cooldownEndDate),
            "joinedGroupAt": FieldValue.serverTimestamp(),
            "joinedGroupId": groupId,
            "adminTrialDaysRemainingAtJoin": adminTrialDaysRemaining,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        AppLogger.main.info("✅ Member approved with cooldown until: \(cooldownEndDate)")
        AppLogger.main.info("   Admin trial days remaining: \(adminTrialDaysRemaining)")
        AppLogger.main.info("   Member cooldown days: \(cooldownDays)")
        
        AppLogger.main.info("✅ Join request approved for \(userName)")
        
        // Post notification to refresh member lists in UI
        NotificationCenter.default.post(
            name: .firebaseGroupMembersDidChange,
            object: nil,
            userInfo: ["groupId": groupId]
        )
    }
    
    /// Deny a join request (admin only)
    @MainActor
    func denyJoinRequest(_ requestId: String) async throws {
        guard let group = currentGroup else {
            throw AppError.groupNotSet
        }
        
        guard let adminId = try? authService.getCurrentUserIdSync(),
              group.adminIds.contains(adminId) else {
            throw GroupError.notAdmin
        }
        
        // Update join request status
        try await db.collection("joinRequests").document(requestId).updateData([
            "status": "denied",
            "deniedBy": adminId,
            "deniedAt": FieldValue.serverTimestamp()
        ])
        
        AppLogger.main.info("❌ Join request denied")
    }
    
    /// Check if user has a pending join request
    @MainActor
    func checkPendingJoinRequest() async -> (hasPending: Bool, groupName: String?) {
        guard let userId = try? authService.getCurrentUserIdSync() else {
            return (false, nil)
        }
        
        do {
            let snapshot = try await db.collection("joinRequests")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: "pending")
                .limit(to: 1)
                .getDocuments()
            
            if let doc = snapshot.documents.first,
               let groupName = doc.data()["groupName"] as? String {
                return (true, groupName)
            }
        } catch {
            AppLogger.main.error("Error checking pending request: \(error)")
        }
        
        return (false, nil)
    }
    
    /// Start listening for join requests (admin only)
    @MainActor
    func startListeningForJoinRequests() {
        guard let group = currentGroup,
              let userId = try? authService.getCurrentUserIdSync(),
              group.adminIds.contains(userId) else {
            print("❌ Not admin or no group - skipping join request listener")
            AppLogger.main.info("Not admin - skipping join request listener")
            return
        }
        
        print("👂 Admin starting to listen for join requests for group: \(group.id)")
        
        // Remove any existing listener
        joinRequestsListener?.remove()
        
        // Start listening to join requests for this group
        joinRequestsListener = db.collection("joinRequests")
            .whereField("groupId", isEqualTo: group.id)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("Error listening to join requests: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Convert to PendingJoinRequest objects
                let requests = snapshot.documents.compactMap { doc -> PendingJoinRequest? in
                    let data = doc.data()
                    guard let userName = data["userName"] as? String,
                          let userId = data["userId"] as? String,
                          let timestamp = data["requestedAt"] as? Timestamp else {
                        return nil
                    }
                    return PendingJoinRequest(
                        id: doc.documentID,
                        userName: userName,
                        userId: userId,
                        requestedAt: timestamp.dateValue()
                    )
                }
                
                Task { @MainActor in
                    self.pendingJoinRequests = requests
                    
                    if !requests.isEmpty {
                        AppLogger.main.info("📨 \(requests.count) pending join request(s)")
                    }
                }
            }
    }
    
    /// Stop listening for join requests
    func stopListeningForJoinRequests() {
        joinRequestsListener?.remove()
        joinRequestsListener = nil
        pendingJoinRequests = []
    }
    
    private func startListeningToGroup(groupId: String) {
        // Remove existing listener if any
        stopListeningToGroup(groupId: groupId)
        
        AppLogger.main.info("🎯 Starting listener for group: \(groupId)")
        
        // Listen to group changes with includeMetadataChanges for immediate updates
        let listener = db.collection("groups").document(groupId)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("Group listener error: \(error)")
                    // Check if it's a permission error
                    if (error as NSError).code == 7 { // Permission denied
                        AppLogger.main.warning("🚫 Permission denied - user likely removed from group")
                        Task { @MainActor in
                            self.handleAccessRevoked()
                        }
                    }
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
                
                // Log the listener update
                AppLogger.main.info("🔄 Group listener update received - checking membership...")
                
                // Check if current user is still in memberIds
                if let userId = try? self.authService.getCurrentUserIdSync(),
                   let memberIds = data["memberIds"] as? [String] {
                    
                    AppLogger.main.info("📊 Membership check:")
                    AppLogger.main.info("   Current User ID: \(userId)")
                    AppLogger.main.info("   Group memberIds: \(memberIds)")
                    AppLogger.main.info("   Is member: \(memberIds.contains(userId))")
                    
                    if !memberIds.contains(userId) {
                        // User has been removed/disabled from the group
                        AppLogger.main.warning("🚫 USER ACCESS REVOKED - removed from memberIds")
                        AppLogger.main.warning("   Triggering access revocation flow...")
                        
                        Task { @MainActor in
                            self.handleAccessRevoked()
                        }
                        
                        // Stop all Firebase services to clear cached data
                        Task { @MainActor in
                            FirebaseServiceManager.shared.stopAllServices()
                        }
                        
                        // Post notification with correct memberId
                        Task { @MainActor in
                            NotificationCenter.default.post(
                                name: .memberAccessRevoked,
                                object: nil,
                                userInfo: [
                                    "memberId": userId,
                                    "message": "Your access has been revoked by the group admin."
                                ]
                            )
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
    
    
    // MARK: - Cleanup
    func cleanup() {
        groupListeners.forEach { $0.value.remove() }
        groupListeners.removeAll()
    }
    
    // MARK: - Member to Admin Transition Methods
    
    /// Clear current group when user no longer has access
    @MainActor
    func clearCurrentGroup() async {
        // Store the group ID before clearing
        let groupId = currentGroup?.id
        
        // Clear the current group
        currentGroup = nil
        
        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: "savedGroupId")
        UserDefaults.standard.removeObject(forKey: "savedInviteCode")
        UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
        
        // Stop any listeners if we had a group
        if let groupId = groupId {
            stopListeningToGroup(groupId: groupId)
        }
        
        // Clear member monitoring timer
        accessCheckTimer?.invalidate()
        accessCheckTimer = nil
        
        // Clear member status listener
        memberStatusListener?.remove()
        memberStatusListener = nil
        
        AppLogger.main.info("✅ Cleared current group due to revoked access")
    }
    
    /// Leave current group as a member
    func leaveGroupAsMember(groupId: String, userId: String) async throws {
        // Remove from group's memberIds
        try await db.collection("groups").document(groupId).updateData([
            "memberIds": FieldValue.arrayRemove([userId]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        // Delete member document
        try await db.collection("groups").document(groupId)
            .collection("members").document(userId).delete()
        
        // Clear current group
        currentGroup = nil
        
        // Stop listening to the old group
        stopListeningToGroup(groupId: groupId)
        
        AppLogger.main.info("✅ User left group as member")
    }
    
    /// Create a new personal group as admin with fresh trial
    func createPersonalGroupAsNewAdmin() async throws {
        guard let userId = try? await authService.getCurrentUserId() else {
            throw AppError.notAuthenticated
        }
        
        // Create new group with fresh 14-day trial
        let groupId = UUID().uuidString
        let inviteCode = generateInviteCode()
        
        // Fresh trial dates (not inherited)
        let trialStart = Date()
        let trialEnd = Calendar.current.date(byAdding: .day, value: 14, to: trialStart)
        
        let group = FirestoreGroup(
            id: groupId,
            name: "My Care Group",
            inviteCode: inviteCode,
            createdBy: userId,
            adminIds: [userId],
            memberIds: [userId],
            writePermissionIds: [userId],
            createdAt: Date(),
            updatedAt: Date(),
            trialStartDate: trialStart,
            trialEndDate: trialEnd,
            hasActiveSubscription: false  // Initially false, set to true when user subscribes
        )
        
        // Save to Firestore
        try await db.collection("groups").document(groupId).setData(group.dictionary)
        
        // Save invite code mapping
        try await db.collection("inviteCodes").document(inviteCode.uppercased()).setData([
            "groupId": groupId,
            "createdAt": FieldValue.serverTimestamp()
        ])
        
        // Update user role
        try await db.collection("users").document(userId).setData([
            "currentRole": "admin",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        currentGroup = group
        
        // Start fresh trial in local subscription manager
        await SubscriptionManager.shared.setTrialState(
            startDate: trialStart,
            endDate: trialEnd!,
            sessionsUsed: 0,
            sessionsRemaining: 999
        )
        
        // Start listening to new group
        startListeningToGroup(groupId: groupId)
        
        AppLogger.main.info("✅ Created new personal group as admin with fresh trial")
    }
    
    /// Update transition tracking after successful transition
    func updateTransitionTracking(userId: String) async throws {
        let userRef = db.collection("users").document(userId)
        
        // Get current count
        let doc = try await userRef.getDocument()
        let currentCount = doc.data()?["transitionCount"] as? Int ?? 0
        
        // Update tracking
        try await userRef.setData([
            "lastTransitionAt": FieldValue.serverTimestamp(),
            "transitionCount": currentCount + 1,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        AppLogger.main.info("✅ Updated transition tracking: count=\(currentCount + 1)")
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
    case transitionCooldown
    
    var errorDescription: String? {
        switch self {
        case .invalidInviteCode:
            return "Invalid invite code"
        case .groupNotFound:
            return "Group not found"
        case .alreadyMember:
            return "You are already a member of this group"
        case .groupFull:
            return "This group is full (maximum 2 members plus admin)"
        case .notAdmin:
            return "Only admins can perform this action"
        case .noWritePermission:
            return "You don't have permission to modify this data"
        case .cannotRemovePrimaryAdmin:
            return "Cannot remove the primary admin from the group"
        case .transitionCooldown:
            return "You must wait 30 days after leaving a group before creating a new one"
        }
    }
}
