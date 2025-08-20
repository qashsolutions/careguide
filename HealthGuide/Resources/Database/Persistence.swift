//
//  Persistence.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/25/25.
//
//  This file provides backward compatibility for SwiftUI previews
//  Production code uses CoreDataStack.swift instead
//

import CoreData

@available(iOS 18.0, *)
struct PersistenceController {
    static let shared = PersistenceController()
    
    // Provide preview context using CoreDataStack for consistency
    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext
        
        // Create sample eldercare data for previews
        do {
            // Sample medication
            let medication = MedicationEntity(context: viewContext)
            medication.id = UUID()
            medication.name = "Aspirin"
            medication.dosage = "81mg"
            medication.unit = "tablet"
            medication.quantity = 1
            medication.isActive = true
            medication.createdAt = Date()
            medication.updatedAt = Date()
            
            // Sample schedule
            let schedule = ScheduleEntity(context: viewContext)
            schedule.id = UUID()
            schedule.frequency = "daily"
            schedule.startDate = Date()
            schedule.timePeriods = ["morning", "evening"] as NSArray
            schedule.activeDays = [1, 2, 3, 4, 5, 6, 7] as NSArray
            schedule.medication = medication
            
            try viewContext.save()
        } catch {
            // Handle preview data creation errors gracefully
            print("Preview data creation failed: \(error.localizedDescription)")
        }
        
        return controller
    }()
    
    // TEMPORARILY DISABLED: Using regular container to avoid CloudKit/Firestore conflicts
    // let container: NSPersistentCloudKitContainer
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        // Use the same model name as CoreDataStack
        // TEMPORARILY DISABLED: CloudKit sync disabled to avoid conflicts with Firestore
        // container = NSPersistentCloudKitContainer(name: "HealthDataModel")
        container = NSPersistentContainer(name: "HealthDataModel")
        
        // Configure the store description
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description")
        }
        
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // TEMPORARILY DISABLED: CloudKit sync to prevent Firestore conflicts
            /*
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.qashsolutions.HealthGuide"
            )
            
            // Enable history tracking (required for CloudKit)
            description.setOption(true as NSNumber, 
                                forKey: NSPersistentHistoryTrackingKey)
            
            // STEP 3: Enable remote change notifications for CloudKit sync
            description.setOption(true as NSNumber, 
                                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            */
            
            // Keep history tracking for potential future use
            description.setOption(true as NSNumber, 
                                forKey: NSPersistentHistoryTrackingKey)
        }
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // Log detailed error for debugging
                print("❌ Core Data failed to load: \(error)")
                print("❌ Error code: \(error.code)")
                print("❌ Error domain: \(error.domain)")
                print("❌ Error userInfo: \(error.userInfo)")
                
                // In production, handle this gracefully
                // For now, fatal error to see the issue
                fatalError("Unresolved error \(error), \(error.userInfo)")
            } else {
                print("✅ Core Data loaded successfully")
                print("✅ Store URL: \(storeDescription.url?.absoluteString ?? "unknown")")
                print("✅ CloudKit enabled: false (disabled to prevent Firestore conflicts)")
                // print("✅ CloudKit container: iCloud.com.qashsolutions.HealthGuide")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
