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
                print("📝 Saved current group ID to UserDefaults: \(group.id)")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
                print("📝 Removed current group ID from UserDefaults")
            }
        }
    }
    @Published var groupMembers: [FirestoreMember] = []
    @Published var isSyncing = false
    @Published var syncError: String?
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("FirebaseGroupService initialized")
        Task {
            await loadSavedGroup()
            
            // TEMPORARY: Force load the Test group if no group is loaded
            if currentGroup == nil {
                print("🔧 TEMPORARY: Attempting to load Test group...")
                await loadGroupById("A4EAF841-9CE2-4FD7-93FB-07FE3FC5B73D")
            }
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
        // Debug check first
        debugCheckUserDefaults()
        
        // Check if we have a saved group ID
        guard let savedGroupId = UserDefaults.standard.string(forKey: "currentFirebaseGroupId") else {
            print("📝 No saved group ID found in UserDefaults")
            
            // Check if there's an old group ID we should migrate
            if let oldGroupId = UserDefaults.standard.string(forKey: "activeGroupID") {
                print("📝 Found old activeGroupID, attempting to load: \(oldGroupId)")
                await loadGroupById(oldGroupId)
            }
            return
        }
        
        print("📝 Found saved group ID: \(savedGroupId)")
        
        // Try to fetch the group from Firebase
        do {
            let groupDoc = try await db.collection("groups").document(savedGroupId).getDocument()
            
            guard let data = groupDoc.data() else {
                print("⚠️ Saved group not found in Firebase")
                UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
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
            print("✅ Restored group: \(group.name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: group.id)
            
        } catch {
            print("❌ Failed to load saved group: \(error)")
            UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
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
    
    // MARK: - Create Group
    func createGroup(name: String, inviteCode: String) async throws -> FirestoreGroup {
        isSyncing = true
        defer { isSyncing = false }
        
        // Ensure user is authenticated
        let userId = try await authService.getCurrentUserId()
        
        // Create group document
        let groupId = UUID().uuidString
        let group = FirestoreGroup(
            id: groupId,
            name: name,
            inviteCode: inviteCode,
            createdBy: userId,
            adminIds: [userId],
            memberIds: [userId],
            writePermissionIds: [userId],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        do {
            // Save to Firestore
            try await db.collection("groups").document(groupId).setData(group.dictionary)
            
            // Also save the invite code mapping for easy lookup
            try await db.collection("inviteCodes").document(inviteCode).setData([
                "groupId": groupId,
                "createdAt": FieldValue.serverTimestamp()
            ])
            
            currentGroup = group
            AppLogger.main.info("✅ Group created in Firebase: \(name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: groupId)
            
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
            // Look up group ID from invite code
            let inviteDoc = try await db.collection("inviteCodes").document(inviteCode).getDocument()
            
            guard let groupId = inviteDoc.data()?["groupId"] as? String else {
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
            
            // Add user to group
            group.memberIds.append(userId)
            // New members get read-only by default
            // Admin can promote them later
            
            // Update Firestore
            try await db.collection("groups").document(groupId).updateData([
                "memberIds": FieldValue.arrayUnion([userId]),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            
            // Save member info
            let member = FirestoreMember(
                id: UUID().uuidString,
                userId: userId,
                groupId: groupId,
                name: memberName,
                role: "member",
                permissions: "read",
                joinedAt: Date()
            )
            
            try await db.collection("groups").document(groupId)
                .collection("members").document(userId)
                .setData(member.dictionary)
            
            currentGroup = group
            AppLogger.main.info("✅ Joined group via Firebase: \(group.name)")
            
            // Start listening to this group
            startListeningToGroup(groupId: groupId)
            
            return group
            
        } catch {
            AppLogger.main.error("❌ Failed to join group: \(error)")
            syncError = error.localizedDescription
            throw error
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
                
                guard let data = snapshot?.data() else { return }
                
                // Manually decode the group
                let group = FirestoreGroup(
                    documentId: snapshot?.documentID,
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
        }
    }
}