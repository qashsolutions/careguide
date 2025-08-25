//
//  FirebaseGroupDataService.swift
//  HealthGuide
//
//  Group-centric data service for shared caregiving
//  All medications, supplements, and diets are stored in group space
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@available(iOS 18.0, *)
@MainActor
final class FirebaseGroupDataService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseGroupDataService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    
    // Current user ID
    private var currentUserId: String? {
        auth.currentUser?.uid
    }
    
    // Current group from FirebaseGroupService
    private var currentGroup: FirestoreGroup? {
        FirebaseGroupService.shared.currentGroup
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🔥 FirebaseGroupDataService initialized")
    }
    
    // MARK: - Group Data Paths
    
    /// Get the path to group data collections
    private func groupPath(_ collection: String) -> CollectionReference? {
        print("🔍 FirebaseGroupDataService.groupPath called for: \(collection)")
        print("   Current group: \(currentGroup?.name ?? "NIL")")
        print("   Group ID: \(currentGroup?.id ?? "NIL")")
        
        guard let groupId = currentGroup?.id else {
            print("❌ No active group - cannot access group data!")
            AppLogger.main.warning("⚠️ No active group - cannot access group data")
            return nil
        }
        
        let path = db.collection("groups").document(groupId).collection(collection)
        print("   ✅ Collection path: \(path.path)")
        return path
    }
    
    // MARK: - Medications
    
    /// Save medication to group space
    func saveMedication(_ medication: Medication) async throws {
        print("\n🔥 FirebaseGroupDataService.saveMedication called")
        print("   Medication: \(medication.name) (ID: \(medication.id))")
        print("   Current group from FirebaseGroupService: \(FirebaseGroupService.shared.currentGroup?.name ?? "NIL")")
        print("   Group ID: \(FirebaseGroupService.shared.currentGroup?.id ?? "NIL")")
        
        guard let collection = groupPath("medications") else {
            print("   ❌ Failed: No group path available")
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId else {
            print("   ❌ Failed: No user ID")
            throw AppError.notAuthenticated
        }
        print("   User ID: \(userId)")
        
        // Check write permission
        guard let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            print("   ❌ Failed: No write permission")
            print("   Write permission IDs: \(currentGroup?.writePermissionIds ?? [])")
            throw AppError.noWritePermission
        }
        
        let firestoreMed = FirestoreMedication(from: medication, groupId: group.id, userId: userId)
        print("   Creating Firestore document with ID: \(firestoreMed.id)")
        
        do {
            print("   Attempting to save to path: \(collection.path)/\(firestoreMed.id)")
            try await collection.document(firestoreMed.id).setData(firestoreMed.dictionary)
            print("   ✅ Successfully saved medication to Firebase!")
            AppLogger.main.info("✅ Saved medication to group: \(medication.name)")
        } catch {
            print("   ❌ Firebase save failed: \(error)")
            print("   Error type: \(type(of: error))")
            AppLogger.main.error("❌ Failed to save medication: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Fetch all medications from group
    func fetchAllMedications() async throws -> [FirestoreMedication] {
        guard let collection = groupPath("medications") else {
            print("📊 Fetched 0 medications from group (no collection)")
            return []
        }
        
        do {
            let snapshot = try await collection.getDocuments()
            let medications = snapshot.documents.compactMap { FirestoreMedication(from: $0) }
            print("📊 Fetched \(medications.count) medications from group")
            return medications
        } catch {
            // Check if this is a permission error
            if let error = error as NSError?,
               error.domain == "FIRFirestoreErrorDomain",
               error.code == 7 { // Permission denied
                print("🚫 Permission denied - posting notification")
                NotificationCenter.default.post(name: .firebasePermissionDenied, object: nil)
            }
            throw error
        }
    }
    
    /// Delete medication from group
    func deleteMedication(_ medicationId: String) async throws {
        guard let collection = groupPath("medications") else {
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId,
              let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            throw AppError.noWritePermission
        }
        
        try await collection.document(medicationId).delete()
        AppLogger.main.info("🗑️ Deleted medication from group")
    }
    
    /// Update medication in group
    func updateMedication(_ medication: Medication) async throws {
        guard let collection = groupPath("medications") else {
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId,
              let groupId = currentGroup?.id,
              let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            throw AppError.noWritePermission
        }
        
        // Convert to FirestoreMedication
        let firestoreMedication = FirestoreMedication(from: medication, groupId: groupId, userId: userId)
        
        do {
            // Update the medication document
            try await collection.document(medication.id.uuidString).setData(firestoreMedication.dictionary, merge: true)
            AppLogger.main.info("✏️ Updated medication in group: \(medication.name)")
        } catch {
            AppLogger.main.error("❌ Failed to update medication: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    // MARK: - Supplements
    
    /// Save supplement to group space
    func saveSupplement(_ supplement: Supplement) async throws {
        print("\n🔥 FirebaseGroupDataService.saveSupplement called")
        print("   Supplement: \(supplement.name) (ID: \(supplement.id))")
        print("   Current group from FirebaseGroupService: \(FirebaseGroupService.shared.currentGroup?.name ?? "NIL")")
        print("   Group ID: \(FirebaseGroupService.shared.currentGroup?.id ?? "NIL")")
        
        guard let collection = groupPath("supplements") else {
            print("   ❌ Failed: No group path available")
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId else {
            print("   ❌ Failed: No user ID")
            throw AppError.notAuthenticated
        }
        print("   User ID: \(userId)")
        
        // Check write permission
        guard let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            print("   ❌ Failed: No write permission")
            print("   Write permission IDs: \(currentGroup?.writePermissionIds ?? [])")
            throw AppError.noWritePermission
        }
        
        let firestoreSup = FirestoreSupplement(from: supplement, groupId: group.id, userId: userId)
        print("   Creating Firestore document with ID: \(firestoreSup.id)")
        
        do {
            print("   Attempting to save to path: \(collection.path)/\(firestoreSup.id)")
            try await collection.document(firestoreSup.id).setData(firestoreSup.dictionary)
            print("   ✅ Successfully saved supplement to Firebase!")
            AppLogger.main.info("✅ Saved supplement to group: \(supplement.name)")
        } catch {
            print("   ❌ Firebase save failed: \(error)")
            print("   Error type: \(type(of: error))")
            AppLogger.main.error("❌ Failed to save supplement: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Fetch all supplements from group
    func fetchAllSupplements() async throws -> [FirestoreSupplement] {
        guard let collection = groupPath("supplements") else {
            print("📊 Fetched 0 supplements from group (no collection)")
            return []
        }
        
        do {
            let snapshot = try await collection.getDocuments()
            let supplements = snapshot.documents.compactMap { FirestoreSupplement(from: $0) }
            print("📊 Fetched \(supplements.count) supplements from group")
            return supplements
        } catch {
            // Check if this is a permission error
            if let error = error as NSError?,
               error.domain == "FIRFirestoreErrorDomain",
               error.code == 7 { // Permission denied
                print("🚫 Permission denied - posting notification")
                NotificationCenter.default.post(name: .firebasePermissionDenied, object: nil)
            }
            throw error
        }
    }
    
    /// Delete supplement from group
    func deleteSupplement(_ supplementId: String) async throws {
        guard let collection = groupPath("supplements") else {
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId,
              let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            throw AppError.noWritePermission
        }
        
        try await collection.document(supplementId).delete()
        AppLogger.main.info("🗑️ Deleted supplement from group")
    }
    
    // MARK: - Diets
    
    /// Save diet to group space
    func saveDiet(_ diet: Diet) async throws {
        guard let collection = groupPath("diets") else {
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId else {
            throw AppError.notAuthenticated
        }
        
        // Check write permission
        guard let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            throw AppError.noWritePermission
        }
        
        let firestoreDiet = FirestoreDiet(from: diet, groupId: group.id, userId: userId)
        
        do {
            try await collection.document(firestoreDiet.id).setData(firestoreDiet.dictionary)
            AppLogger.main.info("✅ Saved diet to group: \(diet.name)")
        } catch {
            AppLogger.main.error("❌ Failed to save diet: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Fetch all diets from group
    func fetchAllDiets() async throws -> [FirestoreDiet] {
        guard let collection = groupPath("diets") else {
            print("📊 Fetched 0 diet items from group (no collection)")
            return []
        }
        
        let snapshot = try await collection.getDocuments()
        let diets = snapshot.documents.compactMap { FirestoreDiet(from: $0) }
        print("📊 Fetched \(diets.count) diet items from group")
        return diets
    }
    
    /// Delete diet from group
    func deleteDiet(_ dietId: String) async throws {
        guard let collection = groupPath("diets") else {
            throw AppError.notAuthenticated
        }
        
        guard let userId = currentUserId,
              let group = currentGroup,
              group.writePermissionIds.contains(userId) else {
            throw AppError.noWritePermission
        }
        
        try await collection.document(dietId).delete()
        AppLogger.main.info("🗑️ Deleted diet from group")
    }
    
    // MARK: - Dose Management
    
    /// Fetch today's doses for the group
    func fetchTodaysDoses() async throws -> [FirestoreDose] {
        guard let dosesPath = groupPath("doses") else {
            print("❌ No group available for fetching doses")
            return []
        }
        
        // Get start and end of today
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let snapshot = try await dosesPath
            .whereField("scheduledTime", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("scheduledTime", isLessThan: Timestamp(date: endOfDay))
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            return FirestoreDose(
                id: data["id"] as? String ?? doc.documentID,
                itemId: data["itemId"] as? String ?? "",
                itemType: data["itemType"] as? String ?? "",
                itemName: data["itemName"] as? String ?? "",
                period: data["period"] as? String ?? "breakfast",
                itemDosage: data["itemDosage"] as? String,
                scheduledTime: (data["scheduledTime"] as? Timestamp)?.dateValue() ?? Date(),
                isTaken: data["isTaken"] as? Bool ?? false,
                takenAt: (data["takenAt"] as? Timestamp)?.dateValue(),
                takenBy: data["takenBy"] as? String,
                takenByName: data["takenByName"] as? String,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }
    
    /// Mark a dose as taken
    func markDoseTaken(doseId: String, itemName: String) async throws {
        guard let dosesPath = groupPath("doses"),
              let userId = currentUserId else {
            throw AppError.notAuthenticated
        }
        
        // Get the current user's name for display
        let userName = UIDevice.current.name
        
        // Check if the dose document exists
        let doseDoc = dosesPath.document(doseId)
        let snapshot = try await doseDoc.getDocument()
        
        if snapshot.exists {
            // Document exists, update it
            try await doseDoc.updateData([
                "isTaken": true,
                "takenAt": Timestamp(date: Date()),
                "takenBy": userId,
                "takenByName": userName,
                "updatedAt": Timestamp(date: Date())
            ])
            print("✅ Updated existing dose as taken in Firebase: \(itemName)")
        } else {
            // Document doesn't exist, we need more info to create it
            // This shouldn't happen if doses are created properly, but handle it gracefully
            print("⚠️ Dose document doesn't exist, cannot mark as taken: \(doseId)")
            throw AppError.internalError("Dose not found. Please refresh and try again.")
        }
        
        // Update badge immediately after marking dose as taken
        await BadgeManager.shared.updateAfterMedicationTaken()
        print("📛 Badge updated after marking dose as taken")
    }
    
    /// Create or update dose for today
    func saveOrUpdateDose(itemId: String, itemName: String, itemType: String, period: String, itemDosage: String?, scheduledTime: Date, isTaken: Bool) async throws {
        guard let dosesPath = groupPath("doses") else {
            throw AppError.notAuthenticated
        }
        
        // Create dose ID based on item, period and date
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: scheduledTime)
        let doseId = "\(itemId)_\(dateComponents.year ?? 0)\(dateComponents.month ?? 0)\(dateComponents.day ?? 0)_\(period)"
        
        let dose = FirestoreDose(
            id: doseId,
            itemId: itemId,
            itemType: itemType,
            itemName: itemName,
            period: period,
            itemDosage: itemDosage,
            scheduledTime: scheduledTime,
            isTaken: isTaken,
            takenAt: isTaken ? Date() : nil,
            takenBy: isTaken ? currentUserId : nil,
            takenByName: isTaken ? UIDevice.current.name : nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        try await dosesPath.document(dose.id).setData(dose.dictionary, merge: true)
        print("✅ Saved/updated dose for \(itemName) at \(period)")
    }
    
    // MARK: - Sync from Core Data
    
    /// Sync all Core Data items to Firebase group (for migration)
    func syncFromCoreData(medications: [Medication], supplements: [Supplement], diets: [Diet]) async throws {
        guard currentGroup != nil else {
            throw AppError.notAuthenticated
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        AppLogger.main.info("🔄 Syncing \(medications.count) medications, \(supplements.count) supplements, \(diets.count) diets to group")
        
        // Save all medications
        for medication in medications {
            try await saveMedication(medication)
        }
        
        // Save all supplements
        for supplement in supplements {
            try await saveSupplement(supplement)
        }
        
        // Save all diets
        for diet in diets {
            try await saveDiet(diet)
        }
        
        lastSyncTime = Date()
        AppLogger.main.info("✅ Sync to Firebase group completed")
    }
    
    // MARK: - Real-time Listeners
    
    private var medicationListener: ListenerRegistration?
    private var supplementListener: ListenerRegistration?
    private var dietListener: ListenerRegistration?
    private var doseListener: ListenerRegistration?
    
    /// Start listening to group data changes
    func startListening() {
        guard let groupId = currentGroup?.id else { return }
        
        // Listen to medications
        medicationListener = db.collection("groups").document(groupId)
            .collection("medications")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.main.error("❌ Medication listener error: \(error)")
                    return
                }
                
                AppLogger.main.info("📱 Medications updated: \(snapshot?.documents.count ?? 0) items")
                
                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .groupDataDidChange,
                    object: nil,
                    userInfo: ["collection": "medications"]
                )
            }
        
        // Listen to supplements
        supplementListener = db.collection("groups").document(groupId)
            .collection("supplements")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.main.error("❌ Supplement listener error: \(error)")
                    return
                }
                
                AppLogger.main.info("📱 Supplements updated: \(snapshot?.documents.count ?? 0) items")
                
                NotificationCenter.default.post(
                    name: .groupDataDidChange,
                    object: nil,
                    userInfo: ["collection": "supplements"]
                )
            }
        
        // Listen to diets
        dietListener = db.collection("groups").document(groupId)
            .collection("diets")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.main.error("❌ Diet listener error: \(error)")
                    return
                }
                
                AppLogger.main.info("📱 Diets updated: \(snapshot?.documents.count ?? 0) items")
                
                NotificationCenter.default.post(
                    name: .groupDataDidChange,
                    object: nil,
                    userInfo: ["collection": "diets"]
                )
            }
        
        // Listen to doses (for real-time updates when medications are taken)
        doseListener = db.collection("groups").document(groupId)
            .collection("doses")
            .whereField("scheduledTime", isGreaterThanOrEqualTo: Timestamp(date: Calendar.current.startOfDay(for: Date())))
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.main.error("❌ Dose listener error: \(error)")
                    return
                }
                
                AppLogger.main.info("📱 Doses updated: \(snapshot?.documents.count ?? 0) items")
                
                // Update badge count when doses change (e.g., when another caregiver marks as taken)
                Task {
                    await BadgeManager.shared.updateBadgeForCurrentPeriod()
                    AppLogger.main.info("📛 Badge updated due to dose changes")
                }
                
                NotificationCenter.default.post(
                    name: .groupDataDidChange,
                    object: nil,
                    userInfo: ["collection": "doses"]
                )
            }
    }
    
    /// Stop listening to group data changes
    func stopListening() {
        medicationListener?.remove()
        supplementListener?.remove()
        dietListener?.remove()
        doseListener?.remove()
        
        medicationListener = nil
        supplementListener = nil
        dietListener = nil
        doseListener = nil
    }
}

// MARK: - Error Extension
extension AppError {
    static var noWritePermission: AppError {
        return AppError.firebaseSyncFailed(reason: "You don't have permission to modify this group's data")
    }
}