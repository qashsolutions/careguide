//
//  CoreDataManager+Notifications.swift
//  HealthGuide
//
//  Swift 6 compliant notification helpers for CoreData
//

import Foundation
import CoreData

// Define a Sendable type for dose data
@available(iOS 18.0, *)
struct DoseData: Sendable {
    let id: UUID
    let scheduledTime: Date
    let isTaken: Bool
    let period: String?
    let medicationName: String?
    let medicationDosage: String?
    let supplementName: String?
    let supplementDosage: String?
    let dietName: String?
    let dietPortion: String?
}

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Fetch Today's Doses
    nonisolated func fetchTodaysDoses(from startDate: Date, to endDate: Date) async -> [DoseData] {
        let container = PersistenceController.shared.container
        
        return await container.performBackgroundTask { context in
            let request = DoseEntity.fetchRequest()
            request.fetchBatchSize = 20  // Optimize memory usage
            request.returnsObjectsAsFaults = true  // Load data lazily
            
            // Fetch doses scheduled for today that haven't been taken
            request.predicate = NSPredicate(
                format: "scheduledTime >= %@ AND scheduledTime < %@ AND isTaken == NO",
                startDate as CVarArg,
                endDate as CVarArg
            )
            
            do {
                let doses = try context.fetch(request)
                // Convert to Sendable struct to avoid passing non-Sendable types across actor boundaries
                return doses.compactMap { dose in
                    guard let id = dose.id,
                          let scheduledTime = dose.scheduledTime else { return nil }
                    
                    return DoseData(
                        id: id,
                        scheduledTime: scheduledTime,
                        isTaken: dose.isTaken,
                        period: dose.period,
                        medicationName: dose.medication?.name,
                        medicationDosage: dose.medication?.dosage,
                        supplementName: dose.supplement?.name,
                        supplementDosage: dose.supplement?.dosage,
                        dietName: dose.diet?.name,
                        dietPortion: dose.diet?.portion
                    )
                }
            } catch {
                print("❌ Failed to fetch doses: \(error)")
                return []
            }
        }
    }
    
    // MARK: - Fetch Doses for Medication
    nonisolated func fetchDosesForMedication(_ medicationId: UUID) async -> [DoseData] {
        let container = PersistenceController.shared.container
        
        return await container.performBackgroundTask { context in
            let request = DoseEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "medication.id == %@ AND isTaken == NO",
                medicationId as CVarArg
            )
            
            do {
                let doses = try context.fetch(request)
                return doses.compactMap { dose in
                    guard let id = dose.id,
                          let scheduledTime = dose.scheduledTime else { return nil }
                    
                    return DoseData(
                        id: id,
                        scheduledTime: scheduledTime,
                        isTaken: dose.isTaken,
                        period: dose.period,
                        medicationName: dose.medication?.name,
                        medicationDosage: dose.medication?.dosage,
                        supplementName: nil,
                        supplementDosage: nil,
                        dietName: nil,
                        dietPortion: nil
                    )
                }
            } catch {
                print("❌ Failed to fetch doses for medication: \(error)")
                return []
            }
        }
    }
    
    // MARK: - Fetch Doses for Supplement
    nonisolated func fetchDosesForSupplement(_ supplementId: UUID) async -> [DoseData] {
        let container = PersistenceController.shared.container
        
        return await container.performBackgroundTask { context in
            let request = DoseEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "supplement.id == %@ AND isTaken == NO",
                supplementId as CVarArg
            )
            
            do {
                let doses = try context.fetch(request)
                return doses.compactMap { dose in
                    guard let id = dose.id,
                          let scheduledTime = dose.scheduledTime else { return nil }
                    
                    return DoseData(
                        id: id,
                        scheduledTime: scheduledTime,
                        isTaken: dose.isTaken,
                        period: dose.period,
                        medicationName: nil,
                        medicationDosage: nil,
                        supplementName: dose.supplement?.name,
                        supplementDosage: dose.supplement?.dosage,
                        dietName: nil,
                        dietPortion: nil
                    )
                }
            } catch {
                print("❌ Failed to fetch doses for supplement: \(error)")
                return []
            }
        }
    }
    
    // MARK: - Mark Dose as Taken
    nonisolated func markDoseAsTaken(_ doseId: UUID) async {
        let container = PersistenceController.shared.container
        
        await container.performBackgroundTask { context in
            let request = DoseEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", doseId as CVarArg)
            request.fetchLimit = 1
            
            do {
                if let dose = try context.fetch(request).first {
                    dose.isTaken = true
                    dose.takenAt = Date()
                    try context.save()
                    print("✅ Marked dose as taken: \(doseId)")
                }
            } catch {
                print("❌ Failed to mark dose as taken: \(error)")
            }
        }
    }
}