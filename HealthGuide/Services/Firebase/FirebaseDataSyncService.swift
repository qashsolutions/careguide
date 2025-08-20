//
//  FirebaseDataSyncService.swift
//  HealthGuide
//
//  Syncs health data to Firebase for group sharing
//

import Foundation
import FirebaseFirestore
import CoreData

@available(iOS 18.0, *)
@MainActor
final class FirebaseDataSyncService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseDataSyncService()
    
    // MARK: - Properties
    private let firebaseGroups = FirebaseGroupService.shared
    @Published var isSyncing = false
    
    // MARK: - Initialization
    private init() {
        setupListeners()
    }
    
    // MARK: - Setup Listeners
    private func setupListeners() {
        // TEMPORARILY DISABLED: This listener causes Core Data threading violations
        // The issue: CoreDataManager uses background context, but this listener
        // tries to access background context entities from main thread
        // TODO: Implement proper context isolation for Firebase sync
        /*
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCoreDataSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
        */
        print("🔥 Firebase auto-sync disabled to prevent Core Data threading violations")
    }
    
    // MARK: - Handle Core Data Saves
    @objc private func handleCoreDataSave(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        // Check if there's an active Firebase group
        guard let activeGroup = firebaseGroups.currentGroup else { return }
        
        Task {
            // Check for new/updated medications
            if let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
                for object in insertedObjects {
                    if let medication = object as? MedicationEntity {
                        await syncMedicationToFirebase(medication, groupId: activeGroup.id)
                    } else if let supplement = object as? SupplementEntity {
                        await syncSupplementToFirebase(supplement, groupId: activeGroup.id)
                    } else if let diet = object as? DietEntity {
                        await syncDietToFirebase(diet, groupId: activeGroup.id)
                    }
                }
            }
            
            if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
                for object in updatedObjects {
                    if let medication = object as? MedicationEntity {
                        await syncMedicationToFirebase(medication, groupId: activeGroup.id)
                    } else if let supplement = object as? SupplementEntity {
                        await syncSupplementToFirebase(supplement, groupId: activeGroup.id)
                    } else if let diet = object as? DietEntity {
                        await syncDietToFirebase(diet, groupId: activeGroup.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Sync Medication
    private func syncMedicationToFirebase(_ medication: MedicationEntity, groupId: String) async {
        guard medication.id != nil,
              medication.name != nil else { return }
        
        // Get current user ID
        let currentUserId = try? await FirebaseAuthService.shared.getCurrentUserId()
        
        // Convert Core Data entity to domain model first, then to Firestore model
        guard let medicationModel = CoreDataConverter.convertToMedication(medication) else { return }
        
        let firestoreMed = FirestoreMedication(
            from: medicationModel,
            groupId: groupId,
            userId: currentUserId ?? "unknown"
        )
        
        do {
            try await firebaseGroups.saveSharedData(
                groupId: groupId,
                collection: "medications",
                documentId: firestoreMed.id,
                data: firestoreMed
            )
            AppLogger.main.info("✅ Medication synced to Firebase: \(medicationModel.name)")
        } catch {
            AppLogger.main.error("❌ Failed to sync medication: \(error)")
        }
    }
    
    // MARK: - Sync Supplement
    private func syncSupplementToFirebase(_ supplement: SupplementEntity, groupId: String) async {
        guard supplement.id != nil,
              supplement.name != nil else { return }
        
        // Get current user ID
        let currentUserId = try? await FirebaseAuthService.shared.getCurrentUserId()
        
        // Convert Core Data entity to domain model first, then to Firestore model
        guard let supplementModel = CoreDataConverter.convertToSupplement(supplement) else { return }
        
        let firestoreSup = FirestoreSupplement(
            from: supplementModel,
            groupId: groupId,
            userId: currentUserId ?? "unknown"
        )
        
        do {
            try await firebaseGroups.saveSharedData(
                groupId: groupId,
                collection: "supplements",
                documentId: firestoreSup.id,
                data: firestoreSup
            )
            AppLogger.main.info("✅ Supplement synced to Firebase: \(supplementModel.name)")
        } catch {
            AppLogger.main.error("❌ Failed to sync supplement: \(error)")
        }
    }
    
    // MARK: - Sync Diet
    private func syncDietToFirebase(_ diet: DietEntity, groupId: String) async {
        guard diet.id != nil,
              diet.name != nil else { return }
        
        // Get current user ID
        let currentUserId = try? await FirebaseAuthService.shared.getCurrentUserId()
        
        // Convert Core Data entity to domain model first, then to Firestore model
        guard let dietModel = CoreDataConverter.convertToDiet(diet) else { return }
        
        let firestoreDiet = FirestoreDiet(
            from: dietModel,
            groupId: groupId,
            userId: currentUserId ?? "unknown"
        )
        
        do {
            try await firebaseGroups.saveSharedData(
                groupId: groupId,
                collection: "diets",
                documentId: firestoreDiet.id,
                data: firestoreDiet
            )
            AppLogger.main.info("✅ Diet synced to Firebase: \(dietModel.name)")
        } catch {
            AppLogger.main.error("❌ Failed to sync diet: \(error)")
        }
    }
    
    // MARK: - Fetch and Merge Firebase Data
    func fetchAndMergeFirebaseData(groupId: String) async {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Fetch medications from Firebase
            let medications = try await firebaseGroups.fetchSharedData(
                groupId: groupId,
                collection: "medications"
            )
            
            // Merge with local Core Data
            for medData in medications {
                await mergeFirebaseMedication(medData)
            }
            
            // Fetch supplements
            let supplements = try await firebaseGroups.fetchSharedData(
                groupId: groupId,
                collection: "supplements"
            )
            
            for supData in supplements {
                await mergeFirebaseSupplement(supData)
            }
            
            AppLogger.main.info("✅ Firebase data merged with local database")
            
        } catch {
            AppLogger.main.error("❌ Failed to fetch Firebase data: \(error)")
        }
    }
    
    // MARK: - Merge Helpers
    private func mergeFirebaseMedication(_ data: [String: Any]) async {
        guard let id = data["id"] as? String,
              let name = data["name"] as? String else { return }
        
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<MedicationEntity> = MedicationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", UUID(uuidString: id)! as CVarArg)
        
        do {
            let existing = try context.fetch(request).first
            
            if existing == nil {
                // Create new medication from Firebase
                let medication = MedicationEntity(context: context)
                medication.id = UUID(uuidString: id)
                medication.name = name
                medication.dosage = data["dosage"] as? String
                medication.notes = data["notes"] as? String
                medication.createdAt = Date()
                medication.updatedAt = Date()
                medication.isActive = true
                
                try context.save()
                AppLogger.main.info("✅ Created medication from Firebase: \(name)")
            }
        } catch {
            AppLogger.main.error("❌ Failed to merge medication: \(error)")
        }
    }
    
    private func mergeFirebaseSupplement(_ data: [String: Any]) async {
        guard let id = data["id"] as? String,
              let name = data["name"] as? String else { return }
        
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<SupplementEntity> = SupplementEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", UUID(uuidString: id)! as CVarArg)
        
        do {
            let existing = try context.fetch(request).first
            
            if existing == nil {
                // Create new supplement from Firebase
                let supplement = SupplementEntity(context: context)
                supplement.id = UUID(uuidString: id)
                supplement.name = name
                supplement.dosage = data["dosage"] as? String
                supplement.notes = data["notes"] as? String
                supplement.createdAt = Date()
                supplement.updatedAt = Date()
                supplement.isActive = true
                
                try context.save()
                AppLogger.main.info("✅ Created supplement from Firebase: \(name)")
            }
        } catch {
            AppLogger.main.error("❌ Failed to merge supplement: \(error)")
        }
    }
}
