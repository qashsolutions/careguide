//
//  FirebasePersonalDataService.swift
//  HealthGuide
//
//  Manages personal health data in Firebase - always syncs regardless of group membership
//  Groups provide read access to member's personal data, but data is owned by the user
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@available(iOS 18.0, *)
@MainActor
final class FirebasePersonalDataService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebasePersonalDataService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private var listeners: [ListenerRegistration] = []
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    
    // Current user's ID - this is the key to personal data
    private var currentUserId: String? {
        return auth.currentUser?.uid
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🔥 FirebasePersonalDataService initialized")
        setupAuthListener()
    }
    
    // MARK: - Auth Listener
    private func setupAuthListener() {
        // Listen for auth state changes
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let userId = user?.uid {
                    AppLogger.main.info("🔥 User authenticated, personal space ready: \(userId)")
                    // User is signed in - their personal space is ready
                    // No need to wait for group creation
                } else {
                    AppLogger.main.info("🔥 User signed out, personal space unavailable")
                    self?.stopAllListeners()
                }
            }
        }
    }
    
    // MARK: - Personal Data Path
    // All data is stored under /users/{userId}/ regardless of group membership
    private func personalPath(_ collection: String) -> CollectionReference? {
        guard let userId = currentUserId else {
            AppLogger.main.error("🔥 No authenticated user for personal data")
            return nil
        }
        return db.collection("users").document(userId).collection(collection)
    }
    
    // MARK: - Save Methods (Always save to personal space)
    
    /// Save medication to user's personal Firebase space
    func saveMedication(_ medication: Medication) async throws {
        guard let collection = personalPath("medications") else {
            throw AppError.notAuthenticated
        }
        
        // Create a personal group ID for single users (using their userId)
        let groupId = FirebaseGroupService.shared.currentGroup?.id ?? currentUserId ?? "personal"
        
        // Use the existing initializer from FirestoreModels
        let firestoreMed = FirestoreMedication(
            from: medication,
            groupId: groupId,
            userId: currentUserId ?? ""
        )
        
        do {
            try await collection.document(firestoreMed.id).setData(firestoreMed.dictionary)
            AppLogger.main.info("✅ Saved medication to personal Firebase: \(medication.name)")
            
            // Also update group if member of one
            await syncToGroupIfMember(medication: firestoreMed)
        } catch {
            AppLogger.main.error("❌ Failed to save medication: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Save supplement to user's personal Firebase space
    func saveSupplement(_ supplement: Supplement) async throws {
        guard let collection = personalPath("supplements") else {
            throw AppError.notAuthenticated
        }
        
        // Create a personal group ID for single users (using their userId)
        let groupId = FirebaseGroupService.shared.currentGroup?.id ?? currentUserId ?? "personal"
        
        // Use the existing initializer from FirestoreModels
        let firestoreSup = FirestoreSupplement(
            from: supplement,
            groupId: groupId,
            userId: currentUserId ?? ""
        )
        
        do {
            try await collection.document(firestoreSup.id).setData(firestoreSup.dictionary)
            AppLogger.main.info("✅ Saved supplement to personal Firebase: \(supplement.name)")
            
            // Also update group if member of one
            await syncToGroupIfMember(supplement: firestoreSup)
        } catch {
            AppLogger.main.error("❌ Failed to save supplement: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Save diet to user's personal Firebase space
    func saveDiet(_ diet: Diet) async throws {
        guard let collection = personalPath("diets") else {
            throw AppError.notAuthenticated
        }
        
        // Create a personal group ID for single users (using their userId)
        let groupId = FirebaseGroupService.shared.currentGroup?.id ?? currentUserId ?? "personal"
        
        // Use the existing initializer from FirestoreModels
        let firestoreDiet = FirestoreDiet(
            from: diet,
            groupId: groupId,
            userId: currentUserId ?? ""
        )
        
        do {
            try await collection.document(firestoreDiet.id).setData(firestoreDiet.dictionary)
            AppLogger.main.info("✅ Saved diet to personal Firebase: \(diet.name)")
            
            // Also update group if member of one
            await syncToGroupIfMember(diet: firestoreDiet)
        } catch {
            AppLogger.main.error("❌ Failed to save diet: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    // MARK: - Group Sync (Optional - only if user is in a group)
    
    private func syncToGroupIfMember(medication: FirestoreMedication) async {
        guard let group = FirebaseGroupService.shared.currentGroup,
              let userId = currentUserId else {
            // No group or not authenticated - that's fine, personal data is saved
            return
        }
        
        // Check if user has write permission in the group
        // Only admins and users with write permission can add/edit medications
        guard group.writePermissionIds.contains(userId) else {
            AppLogger.main.warning("⚠️ User doesn't have write permission in group - skipping group sync")
            // Members with read-only permission can still save to personal space
            // but cannot sync to group (cannot add medications visible to others)
            return
        }
        
        // Create a reference in the group pointing to user's personal data
        let groupRef = db.collection("groups").document(group.id)
            .collection("member_medications").document("\(userId)_\(medication.id)")
        
        let reference = [
            "userId": userId,
            "medicationId": medication.id,
            "personalDataPath": "users/\(userId)/medications/\(medication.id)",
            "updatedAt": FieldValue.serverTimestamp()
        ] as [String : Any]
        
        do {
            try await groupRef.setData(reference)
            AppLogger.main.debug("✅ Synced medication reference to group")
        } catch {
            AppLogger.main.error("⚠️ Failed to sync to group (non-critical): \(error)")
            // Don't throw - group sync is optional
        }
    }
    
    private func syncToGroupIfMember(supplement: FirestoreSupplement) async {
        guard let group = FirebaseGroupService.shared.currentGroup,
              let userId = currentUserId else {
            return
        }
        
        // Check if user has write permission in the group
        guard group.writePermissionIds.contains(userId) else {
            AppLogger.main.warning("⚠️ User doesn't have write permission in group - skipping group sync")
            return
        }
        
        let groupRef = db.collection("groups").document(group.id)
            .collection("member_supplements").document("\(userId)_\(supplement.id)")
        
        let reference = [
            "userId": userId,
            "supplementId": supplement.id,
            "personalDataPath": "users/\(userId)/supplements/\(supplement.id)",
            "updatedAt": FieldValue.serverTimestamp()
        ] as [String : Any]
        
        do {
            try await groupRef.setData(reference)
            AppLogger.main.debug("✅ Synced supplement reference to group")
        } catch {
            AppLogger.main.error("⚠️ Failed to sync to group (non-critical): \(error)")
        }
    }
    
    private func syncToGroupIfMember(diet: FirestoreDiet) async {
        guard let group = FirebaseGroupService.shared.currentGroup,
              let userId = currentUserId else {
            return
        }
        
        // Check if user has write permission in the group
        guard group.writePermissionIds.contains(userId) else {
            AppLogger.main.warning("⚠️ User doesn't have write permission in group - skipping group sync")
            return
        }
        
        let groupRef = db.collection("groups").document(group.id)
            .collection("member_diets").document("\(userId)_\(diet.id)")
        
        let reference = [
            "userId": userId,
            "dietId": diet.id,
            "personalDataPath": "users/\(userId)/diets/\(diet.id)",
            "updatedAt": FieldValue.serverTimestamp()
        ] as [String : Any]
        
        do {
            try await groupRef.setData(reference)
            AppLogger.main.debug("✅ Synced diet reference to group")
        } catch {
            AppLogger.main.error("⚠️ Failed to sync to group (non-critical): \(error)")
        }
    }
    
    // MARK: - Fetch Methods (From personal space and group members)
    
    /// Fetch all medications (personal + group members if in a group)
    func fetchAllMedications() async throws -> [FirestoreMedication] {
        var allMedications: [FirestoreMedication] = []
        
        // 1. Always fetch user's own medications
        if let collection = personalPath("medications") {
            let snapshot = try await collection.getDocuments()
            let personal = snapshot.documents.compactMap { FirestoreMedication(from: $0) }
            allMedications.append(contentsOf: personal)
            AppLogger.main.info("📊 Fetched \(personal.count) personal medications")
        }
        
        // 2. If in a group, fetch other members' medications
        if let group = FirebaseGroupService.shared.currentGroup {
            let memberMeds = try await fetchGroupMemberMedications(groupId: group.id)
            allMedications.append(contentsOf: memberMeds)
            AppLogger.main.info("📊 Fetched \(memberMeds.count) group member medications")
        }
        
        return allMedications
    }
    
    private func fetchGroupMemberMedications(groupId: String) async throws -> [FirestoreMedication] {
        guard let userId = currentUserId else { return [] }
        
        // Get all medication references from group
        let snapshot = try await db.collection("groups").document(groupId)
            .collection("member_medications").getDocuments()
        
        var medications: [FirestoreMedication] = []
        
        for doc in snapshot.documents {
            guard let memberUserId = doc.data()["userId"] as? String,
                  memberUserId != userId, // Skip own medications (already fetched)
                  let path = doc.data()["personalDataPath"] as? String else {
                continue
            }
            
            // Fetch the actual medication from member's personal space
            let components = path.split(separator: "/")
            if components.count == 4 {
                let memberDoc = try await db.document(path).getDocument()
                if let medication = FirestoreMedication(from: memberDoc) {
                    medications.append(medication)
                }
            }
        }
        
        return medications
    }
    
    /// Fetch all supplements (personal + group members if in a group)
    public func fetchAllSupplements() async throws -> [FirestoreSupplement] {
        var allSupplements: [FirestoreSupplement] = []
        
        // 1. Always fetch user's own supplements
        if let collection = personalPath("supplements") {
            let snapshot = try await collection.getDocuments()
            let personal = snapshot.documents.compactMap { FirestoreSupplement(from: $0) }
            allSupplements.append(contentsOf: personal)
            AppLogger.main.info("📊 Fetched \(personal.count) personal supplements")
        }
        
        // 2. If in a group, fetch other members' supplements
        if let group = FirebaseGroupService.shared.currentGroup {
            let memberSups = try await fetchGroupMemberSupplements(groupId: group.id)
            allSupplements.append(contentsOf: memberSups)
            AppLogger.main.info("📊 Fetched \(memberSups.count) group member supplements")
        }
        
        return allSupplements
    }
    
    private func fetchGroupMemberSupplements(groupId: String) async throws -> [FirestoreSupplement] {
        guard let userId = currentUserId else { return [] }
        
        let snapshot = try await db.collection("groups").document(groupId)
            .collection("member_supplements").getDocuments()
        
        var supplements: [FirestoreSupplement] = []
        
        for doc in snapshot.documents {
            guard let memberUserId = doc.data()["userId"] as? String,
                  memberUserId != userId, // Skip own supplements
                  let path = doc.data()["personalDataPath"] as? String else {
                continue
            }
            
            let memberDoc = try await db.document(path).getDocument()
            if let supplement = FirestoreSupplement(from: memberDoc) {
                supplements.append(supplement)
            }
        }
        
        return supplements
    }
    
    /// Fetch all diets (personal + group members if in a group)
    public func fetchAllDiets() async throws -> [FirestoreDiet] {
        var allDiets: [FirestoreDiet] = []
        
        // 1. Always fetch user's own diets
        if let collection = personalPath("diets") {
            let snapshot = try await collection.getDocuments()
            let personal = snapshot.documents.compactMap { FirestoreDiet(from: $0) }
            allDiets.append(contentsOf: personal)
            AppLogger.main.info("📊 Fetched \(personal.count) personal diet items")
        }
        
        // 2. If in a group, fetch other members' diets
        if let group = FirebaseGroupService.shared.currentGroup {
            let memberDiets = try await fetchGroupMemberDiets(groupId: group.id)
            allDiets.append(contentsOf: memberDiets)
            AppLogger.main.info("📊 Fetched \(memberDiets.count) group member diet items")
        }
        
        return allDiets
    }
    
    private func fetchGroupMemberDiets(groupId: String) async throws -> [FirestoreDiet] {
        guard let userId = currentUserId else { return [] }
        
        let snapshot = try await db.collection("groups").document(groupId)
            .collection("member_diets").getDocuments()
        
        var diets: [FirestoreDiet] = []
        
        for doc in snapshot.documents {
            guard let memberUserId = doc.data()["userId"] as? String,
                  memberUserId != userId, // Skip own diets
                  let path = doc.data()["personalDataPath"] as? String else {
                continue
            }
            
            let memberDoc = try await db.document(path).getDocument()
            if let diet = FirestoreDiet(from: memberDoc) {
                diets.append(diet)
            }
        }
        
        return diets
    }
    
    // MARK: - Sync All Existing Data
    
    /// Sync all existing local data to Firebase personal space
    /// This is called automatically when creating a group to ensure all data is in Firebase
    func syncAllExistingData() async throws {
        guard currentUserId != nil else {
            throw AppError.notAuthenticated
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        AppLogger.main.info("🔄 Starting sync of all existing data to Firebase...")
        
        // Fetch all local data from Core Data
        let coreDataManager = CoreDataManager.shared
        
        // Sync medications
        let medications = try await coreDataManager.fetchMedications()
        for medication in medications {
            // Check if already exists in Firebase before saving
            if let collection = personalPath("medications") {
                let doc = try await collection.document(medication.id.uuidString).getDocument()
                if !doc.exists {
                    try await saveMedication(medication)
                }
            }
        }
        AppLogger.main.info("✅ Synced \(medications.count) medications")
        
        // Sync supplements
        let supplements = try await coreDataManager.fetchSupplements()
        for supplement in supplements {
            // Check if already exists in Firebase before saving
            if let collection = personalPath("supplements") {
                let doc = try await collection.document(supplement.id.uuidString).getDocument()
                if !doc.exists {
                    try await saveSupplement(supplement)
                }
            }
        }
        AppLogger.main.info("✅ Synced \(supplements.count) supplements")
        
        // Sync diets
        let diets = try await coreDataManager.fetchDietItems()
        for diet in diets {
            // Check if already exists in Firebase before saving
            if let collection = personalPath("diets") {
                let doc = try await collection.document(diet.id.uuidString).getDocument()
                if !doc.exists {
                    try await saveDiet(diet)
                }
            }
        }
        AppLogger.main.info("✅ Synced \(diets.count) diet items")
        
        lastSyncDate = Date()
        AppLogger.main.info("🎉 All existing data synced to Firebase successfully!")
    }
    
    // MARK: - Cleanup
    
    private func stopAllListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
}