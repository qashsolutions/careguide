//
//  FirebaseHealthService.swift
//  HealthGuide
//
//  Main service for health data management via Firebase
//  Provides real-time sync for medications, supplements, doses across caregivers
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@available(iOS 18.0, *)
@MainActor
final class FirebaseHealthService: ObservableObject {
    
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var cancellables = Set<AnyCancellable>()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    @Published var medications: [FirestoreMedication] = []
    @Published var supplements: [FirestoreSupplement] = []
    @Published var diets: [FirestoreDiet] = []
    @Published var doses: [FirestoreDose] = []
    @Published var schedules: [FirestoreSchedule] = []
    @Published var contacts: [FirestoreContact] = []
    @Published var memos: [FirestoreCareMemo] = []
    @Published var documents: [FirestoreDocument] = []
    @Published var conflicts: [FirestoreConflict] = []
    
    @Published var isLoading = false
    @Published var error: Error?
    
    private var currentGroupId: String?
    private var currentUserId: String?
    
    // MARK: - Initialization
    
    init() {
        setupAuthListener()
    }
    
    deinit {
        // Clean up in a non-isolated context
        Task { @MainActor [weak self] in
            self?.cleanup()
        }
    }
    
    // MARK: - Setup
    
    private func setupAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUserId = user?.uid
                if user == nil {
                    self?.stopAllListeners()
                    self?.clearAllData()
                }
            }
        }
    }
    
    private func cleanup() {
        stopAllListeners()
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
            authStateHandle = nil
        }
    }
    
    func setCurrentGroup(_ groupId: String) {
        guard groupId != currentGroupId else { return }
        currentGroupId = groupId
        stopAllListeners()
        startListeners(for: groupId)
    }
    
    // MARK: - Real-time Listeners
    
    private func startListeners(for groupId: String) {
        // Medications listener
        let medicationsListener = db.collection("groups")
            .document(groupId)
            .collection("medications")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = error
                        AppLogger.main.error("Error listening to medications: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    self?.medications = documents.compactMap { FirestoreMedication(from: $0) }
                    AppLogger.main.info("✅ Updated \(documents.count) medications from Firebase")
                }
            }
        listeners.append(medicationsListener)
        
        // Supplements listener
        let supplementsListener = db.collection("groups")
            .document(groupId)
            .collection("supplements")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = error
                        AppLogger.main.error("Error listening to supplements: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    self?.supplements = documents.compactMap { FirestoreSupplement(from: $0) }
                    AppLogger.main.info("✅ Updated \(documents.count) supplements from Firebase")
                }
            }
        listeners.append(supplementsListener)
        
        // Diets listener
        let dietsListener = db.collection("groups")
            .document(groupId)
            .collection("diets")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = error
                        AppLogger.main.error("Error listening to diets: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    self?.diets = documents.compactMap { FirestoreDiet(from: $0) }
                    AppLogger.main.info("✅ Updated \(documents.count) diets from Firebase")
                }
            }
        listeners.append(dietsListener)
        
        // Doses listener (today's doses)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let dosesListener = db.collection("groups")
            .document(groupId)
            .collection("doses")
            .whereField("scheduledTime", isGreaterThanOrEqualTo: startOfDay)
            .whereField("scheduledTime", isLessThan: endOfDay)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = error
                        AppLogger.main.error("Error listening to doses: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    self?.doses = documents.compactMap { FirestoreDose(from: $0) }
                    AppLogger.main.info("✅ Updated \(documents.count) doses from Firebase")
                }
            }
        listeners.append(dosesListener)
        
        // Schedules listener
        let schedulesListener = db.collection("groups")
            .document(groupId)
            .collection("schedules")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = error
                        AppLogger.main.error("Error listening to schedules: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    self?.schedules = documents.compactMap { FirestoreSchedule(from: $0) }
                    AppLogger.main.info("✅ Updated \(documents.count) schedules from Firebase")
                }
            }
        listeners.append(schedulesListener)
        
        // Contacts listener
        let contactsListener = db.collection("groups")
            .document(groupId)
            .collection("contacts")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error = error {
                        self?.error = error
                        AppLogger.main.error("Error listening to contacts: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let documents = snapshot?.documents else { return }
                    self?.contacts = documents.compactMap { FirestoreContact(from: $0) }
                    AppLogger.main.info("✅ Updated \(documents.count) contacts from Firebase")
                }
            }
        listeners.append(contactsListener)
    }
    
    private func stopAllListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }
    
    private func clearAllData() {
        medications = []
        supplements = []
        diets = []
        doses = []
        schedules = []
        contacts = []
        memos = []
        documents = []
        conflicts = []
    }
    
    // MARK: - Limit Validation
    
    private func checkMedicationLimit() async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        // Get current medication count for this group
        let snapshot = try await db.collection("groups")
            .document(groupId)
            .collection("medications")
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let currentCount = snapshot.documents.count
        
        if currentCount >= Configuration.HealthLimits.maxMedications {
            throw AppError.medicationLimitExceeded(
                current: currentCount,
                maximum: Configuration.HealthLimits.maxMedications
            )
        }
    }
    
    private func checkSupplementLimit() async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        // Get current supplement count for this group
        let snapshot = try await db.collection("groups")
            .document(groupId)
            .collection("supplements")
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let currentCount = snapshot.documents.count
        
        if currentCount >= Configuration.HealthLimits.maxSupplements {
            throw AppError.supplementLimitExceeded(
                current: currentCount,
                maximum: Configuration.HealthLimits.maxSupplements
            )
        }
    }
    
    private func checkDietLimit(mealType: String?) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        // Get total diet count for this group
        let totalSnapshot = try await db.collection("groups")
            .document(groupId)
            .collection("diets")
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        let totalCount = totalSnapshot.documents.count
        
        if totalCount >= Configuration.HealthLimits.maxDietItems {
            throw AppError.dietLimitExceeded(
                current: totalCount,
                maximum: Configuration.HealthLimits.maxDietItems
            )
        }
        
        // Check per-meal-type limits if mealType is provided
        if let mealType = mealType {
            let mealSnapshot = try await db.collection("groups")
                .document(groupId)
                .collection("diets")
                .whereField("isActive", isEqualTo: true)
                .whereField("mealType", isEqualTo: mealType)
                .getDocuments()
            
            let mealCount = mealSnapshot.documents.count
            let maxForMeal: Int
            
            switch mealType.lowercased() {
            case "breakfast":
                maxForMeal = Configuration.HealthLimits.maxBreakfastItems
            case "lunch":
                maxForMeal = Configuration.HealthLimits.maxLunchItems
            case "dinner":
                maxForMeal = Configuration.HealthLimits.maxDinnerItems
            case "snack":
                maxForMeal = Configuration.HealthLimits.maxSnackItems
            default:
                maxForMeal = Configuration.HealthLimits.maxBreakfastItems // Default
            }
            
            if mealCount >= maxForMeal {
                throw AppError.mealLimitExceeded(
                    mealType: mealType,
                    current: mealCount,
                    maximum: maxForMeal
                )
            }
        }
    }
    
    private func validateFrequency(frequency: Schedule.Frequency, for type: HealthItemType) throws {
        let maxFrequency: Int
        
        switch type {
        case .medication:
            maxFrequency = Configuration.HealthLimits.maxMedicationFrequency
        case .supplement:
            maxFrequency = Configuration.HealthLimits.maxSupplementFrequency
        case .diet:
            maxFrequency = Configuration.HealthLimits.maxDinnerItems // Diets don't have daily frequency limits
            return // Skip validation for diets
        }
        
        let dailyCount = frequency.count
        if dailyCount > maxFrequency {
            throw AppError.frequencyLimitExceeded(
                itemType: type.rawValue,
                requestedFrequency: dailyCount,
                maximum: maxFrequency
            )
        }
    }
    
    // MARK: - Medications CRUD
    
    func saveMedication(_ medication: Medication) async throws {
        print("🔥 FirebaseHealthService.saveMedication called")
        print("   Medication: \(medication.name)")
        print("   Current Group ID: \(currentGroupId ?? "nil")")
        print("   Current User ID: \(currentUserId ?? "nil")")
        
        // Get the current user ID directly from Firebase Auth
        let userId = Auth.auth().currentUser?.uid ?? currentUserId
        
        print("   Auth.currentUser?.uid: \(Auth.auth().currentUser?.uid ?? "nil")")
        
        guard let groupId = currentGroupId,
              let validUserId = userId else {
            print("❌ Missing groupId or userId")
            print("   groupId: \(currentGroupId ?? "nil")")
            print("   userId: \(userId ?? "nil")")
            print("   Auth.currentUser: \(Auth.auth().currentUser?.uid ?? "nil")")
            throw AppError.notAuthenticated
        }
        
        // Check medication limit for the group
        try await checkMedicationLimit()
        
        // Validate frequency
        try validateFrequency(frequency: medication.schedule.frequency, for: .medication)
        
        // First save schedule if it exists
        let firestoreSchedule = FirestoreSchedule(from: medication.schedule, groupId: groupId, userId: validUserId)
        try await saveSchedule(firestoreSchedule)
        
        // Then save medication with schedule reference
        var firestoreMed = FirestoreMedication(from: medication, groupId: groupId, userId: validUserId)
        firestoreMed.scheduleId = firestoreSchedule.id
        
        let docRef = db.collection("groups")
            .document(groupId)
            .collection("medications")
            .document(firestoreMed.id)
        
        try await docRef.setData(firestoreMed.dictionary)
        
        // Generate doses for the medication
        await generateDoses(for: firestoreMed, schedule: medication.schedule)
        
        AppLogger.main.info("✅ Saved medication: \(medication.name) to Firebase")
    }
    
    func updateMedication(_ medication: FirestoreMedication) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        var updated = medication
        updated.updatedAt = Date()
        
        let docRef = db.collection("groups")
            .document(groupId)
            .collection("medications")
            .document(medication.id)
        
        try await docRef.setData(updated.dictionary, merge: true)
        AppLogger.main.info("✅ Updated medication: \(medication.name)")
    }
    
    func deleteMedication(_ medicationId: String) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        // Delete associated doses
        let dosesToDelete = doses.filter { $0.itemId == medicationId && $0.itemType == "medication" }
        for dose in dosesToDelete {
            try await deleteDose(dose.id)
        }
        
        // Delete medication
        try await db.collection("groups")
            .document(groupId)
            .collection("medications")
            .document(medicationId)
            .delete()
        
        AppLogger.main.info("✅ Deleted medication and associated doses")
    }
    
    // MARK: - Supplements CRUD
    
    func saveSupplement(_ supplement: Supplement) async throws {
        print("🔥 FirebaseHealthService.saveSupplement called")
        print("   Supplement: \(supplement.name)")
        print("   Current Group ID: \(currentGroupId ?? "nil")")
        print("   Current User ID: \(currentUserId ?? "nil")")
        
        // Get the current user ID directly from Firebase Auth
        let userId = Auth.auth().currentUser?.uid ?? currentUserId
        
        print("   Auth.currentUser?.uid: \(Auth.auth().currentUser?.uid ?? "nil")")
        
        guard let groupId = currentGroupId,
              let validUserId = userId else {
            print("❌ Missing groupId or userId")
            throw AppError.notAuthenticated
        }
        
        // Check supplement limit for the group
        try await checkSupplementLimit()
        
        // Validate frequency
        try validateFrequency(frequency: supplement.schedule.frequency, for: .supplement)
        
        // First save schedule
        let firestoreSchedule = FirestoreSchedule(from: supplement.schedule, groupId: groupId, userId: validUserId)
        try await saveSchedule(firestoreSchedule)
        
        // Then save supplement with schedule reference
        var firestoreSup = FirestoreSupplement(from: supplement, groupId: groupId, userId: validUserId)
        firestoreSup.scheduleId = firestoreSchedule.id
        
        let docRef = db.collection("groups")
            .document(groupId)
            .collection("supplements")
            .document(firestoreSup.id)
        
        try await docRef.setData(firestoreSup.dictionary)
        
        // Generate doses
        await generateDosesForSupplement(firestoreSup, schedule: supplement.schedule)
        
        AppLogger.main.info("✅ Saved supplement: \(supplement.name) to Firebase")
    }
    
    // MARK: - Diets CRUD
    
    func saveDiet(_ diet: Diet) async throws {
        print("🔥 FirebaseHealthService.saveDiet called")
        print("   Diet: \(diet.name)")
        print("   Current Group ID: \(currentGroupId ?? "nil")")
        print("   Current User ID: \(currentUserId ?? "nil")")
        
        // Get the current user ID directly from Firebase Auth
        let userId = Auth.auth().currentUser?.uid ?? currentUserId
        
        print("   Auth.currentUser?.uid: \(Auth.auth().currentUser?.uid ?? "nil")")
        
        guard let groupId = currentGroupId,
              let validUserId = userId else {
            print("❌ Missing groupId or userId")
            throw AppError.notAuthenticated
        }
        
        // Check diet limit for the group and meal type
        let mealType = diet.mealType?.rawValue
        try await checkDietLimit(mealType: mealType)
        
        // First save schedule
        let firestoreSchedule = FirestoreSchedule(from: diet.schedule, groupId: groupId, userId: validUserId)
        try await saveSchedule(firestoreSchedule)
        
        // Then save diet with schedule reference
        var firestoreDiet = FirestoreDiet(from: diet, groupId: groupId, userId: validUserId)
        firestoreDiet.scheduleId = firestoreSchedule.id
        
        let docRef = db.collection("groups")
            .document(groupId)
            .collection("diets")
            .document(firestoreDiet.id)
        
        try await docRef.setData(firestoreDiet.dictionary)
        
        // Generate doses for the diet
        await generateDosesForDiet(firestoreDiet, schedule: diet.schedule)
        
        AppLogger.main.info("✅ Saved diet: \(diet.name) to Firebase")
    }
    
    // MARK: - Doses Management
    
    func markDoseTaken(_ doseId: String, taken: Bool = true, notes: String? = nil) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        var updates: [String: Any] = [
            "isTaken": taken,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if taken {
            updates["takenAt"] = FieldValue.serverTimestamp()
        } else {
            updates["takenAt"] = FieldValue.delete()
        }
        
        if let notes = notes {
            updates["notes"] = notes
        }
        
        try await db.collection("groups")
            .document(groupId)
            .collection("doses")
            .document(doseId)
            .updateData(updates)
        
        AppLogger.main.info("✅ Marked dose as \(taken ? "taken" : "not taken")")
    }
    
    func getTodaysDoses() async throws -> [FirestoreDose] {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let snapshot = try await db.collection("groups")
            .document(groupId)
            .collection("doses")
            .whereField("scheduledTime", isGreaterThanOrEqualTo: startOfDay)
            .whereField("scheduledTime", isLessThan: endOfDay)
            .getDocuments()
        
        return snapshot.documents.compactMap { FirestoreDose(from: $0) }
    }
    
    private func generateDoses(for medication: FirestoreMedication, schedule: Schedule) async {
        guard let groupId = currentGroupId,
              let _ = Auth.auth().currentUser?.uid ?? currentUserId else { return }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Generate doses for next 7 days
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            
            if schedule.isScheduledForDate(date) {
                let scheduledDoses = schedule.dosesForDate(date)
                
                for dose in scheduledDoses {
                    // Determine period from dose time
                    let hour = calendar.component(.hour, from: dose.time)
                    let period: String
                    if hour < 12 {
                        period = "breakfast"
                    } else if hour < 17 {
                        period = "lunch"
                    } else {
                        period = "dinner"
                    }
                    
                    let firestoreDose = FirestoreDose(
                        id: UUID().uuidString,
                        itemId: medication.id,
                        itemType: "medication",
                        itemName: medication.name,
                        period: period,
                        itemDosage: medication.dosage,
                        scheduledTime: dose.time,
                        isTaken: false,
                        takenAt: nil,
                        takenBy: nil,
                        takenByName: nil,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    
                    do {
                        try await db.collection("groups")
                            .document(groupId)
                            .collection("doses")
                            .document(firestoreDose.id)
                            .setData(firestoreDose.dictionary)
                    } catch {
                        AppLogger.main.error("Failed to generate dose: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func generateDosesForSupplement(_ supplement: FirestoreSupplement, schedule: Schedule) async {
        guard let groupId = currentGroupId,
              let _ = Auth.auth().currentUser?.uid ?? currentUserId else { return }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Generate doses for next 7 days
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            
            if schedule.isScheduledForDate(date) {
                let scheduledDoses = schedule.dosesForDate(date)
                
                for dose in scheduledDoses {
                    // Determine period from dose time
                    let hour = calendar.component(.hour, from: dose.time)
                    let period: String
                    if hour < 12 {
                        period = "breakfast"
                    } else if hour < 17 {
                        period = "lunch"
                    } else {
                        period = "dinner"
                    }
                    
                    let firestoreDose = FirestoreDose(
                        id: UUID().uuidString,
                        itemId: supplement.id,
                        itemType: "supplement",
                        itemName: supplement.name,
                        period: period,
                        itemDosage: supplement.dosage,
                        scheduledTime: dose.time,
                        isTaken: false,
                        takenAt: nil,
                        takenBy: nil,
                        takenByName: nil,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    
                    do {
                        try await db.collection("groups")
                            .document(groupId)
                            .collection("doses")
                            .document(firestoreDose.id)
                            .setData(firestoreDose.dictionary)
                    } catch {
                        AppLogger.main.error("Failed to generate dose: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func generateDosesForDiet(_ diet: FirestoreDiet, schedule: Schedule) async {
        guard let groupId = currentGroupId,
              let _ = Auth.auth().currentUser?.uid ?? currentUserId else { return }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Generate doses for next 7 days
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            
            if schedule.isScheduledForDate(date) {
                let scheduledDoses = schedule.dosesForDate(date)
                
                for dose in scheduledDoses {
                    // Determine period from dose time
                    let hour = calendar.component(.hour, from: dose.time)
                    let period: String
                    if hour < 12 {
                        period = "breakfast"
                    } else if hour < 17 {
                        period = "lunch"
                    } else {
                        period = "dinner"
                    }
                    
                    let firestoreDose = FirestoreDose(
                        id: UUID().uuidString,
                        itemId: diet.id,
                        itemType: "diet",
                        itemName: diet.name,
                        period: period,
                        itemDosage: diet.portion,
                        scheduledTime: dose.time,
                        isTaken: false,
                        takenAt: nil,
                        takenBy: nil,
                        takenByName: nil,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    
                    do {
                        try await db.collection("groups")
                            .document(groupId)
                            .collection("doses")
                            .document(firestoreDose.id)
                            .setData(firestoreDose.dictionary)
                    } catch {
                        AppLogger.main.error("Failed to generate dose: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: - Schedules Management
    
    private func saveSchedule(_ schedule: FirestoreSchedule) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        try await db.collection("groups")
            .document(groupId)
            .collection("schedules")
            .document(schedule.id)
            .setData(schedule.dictionary)
    }
    
    func getSchedule(by id: String) async throws -> FirestoreSchedule? {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        let doc = try await db.collection("groups")
            .document(groupId)
            .collection("schedules")
            .document(id)
            .getDocument()
        
        return FirestoreSchedule(from: doc)
    }
    
    private func deleteDose(_ doseId: String) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        try await db.collection("groups")
            .document(groupId)
            .collection("doses")
            .document(doseId)
            .delete()
    }
    
    // MARK: - Contacts Management
    
    func saveContact(_ contact: FirestoreContact) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        try await db.collection("groups")
            .document(groupId)
            .collection("contacts")
            .document(contact.id)
            .setData(contact.dictionary)
        
        AppLogger.main.info("✅ Saved contact: \(contact.name)")
    }
    
    func deleteContact(_ contactId: String) async throws {
        guard let groupId = currentGroupId else {
            throw AppError.notAuthenticated
        }
        
        try await db.collection("groups")
            .document(groupId)
            .collection("contacts")
            .document(contactId)
            .delete()
        
        AppLogger.main.info("✅ Deleted contact")
    }
    
    // MARK: - Helper Methods
    
    func getMedication(by id: String) -> FirestoreMedication? {
        medications.first { $0.id == id }
    }
    
    func getSupplement(by id: String) -> FirestoreSupplement? {
        supplements.first { $0.id == id }
    }
    
    func getDiet(by id: String) -> FirestoreDiet? {
        diets.first { $0.id == id }
    }
    
    func getUpcomingDoses(limit: Int = 10) -> [FirestoreDose] {
        let now = Date()
        return doses
            .filter { !$0.isTaken && $0.scheduledTime > now }
            .sorted { $0.scheduledTime < $1.scheduledTime }
            .prefix(limit)
            .map { $0 }
    }
    
    func getOverdueDoses() -> [FirestoreDose] {
        let now = Date()
        return doses
            .filter { !$0.isTaken && $0.scheduledTime < now }
            .sorted { $0.scheduledTime < $1.scheduledTime }
    }
}
