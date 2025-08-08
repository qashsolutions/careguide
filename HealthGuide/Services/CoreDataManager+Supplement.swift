//
//  CoreDataManager+Supplement.swift
//  HealthGuide
//
//  Supplement-specific Core Data operations
//  Handles CRUD operations for supplements with validation
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Supplement Operations
    
    /// Save a supplement to the persistent store
    func saveSupplement(_ supplement: Supplement) async throws {
        // Validate the supplement
        try supplement.validate()
        
        try await context.perform { @Sendable [self, context] in
            let entity = SupplementEntity(context: context)
            entity.id = supplement.id
            entity.name = supplement.name
            entity.dosage = supplement.dosage
            entity.unit = supplement.unit.rawValue
            entity.notes = supplement.notes
            entity.isActive = supplement.isActive
            entity.createdAt = supplement.createdAt
            entity.updatedAt = Date()
            entity.category = supplement.category?.rawValue
            entity.brand = supplement.brand
            
            // Create schedule
            entity.schedule = createScheduleEntity(from: supplement.schedule, in: context)
            
            // Pre-create doses for scheduled days
            createDosesForSupplement(entity, schedule: supplement.schedule, in: context)
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Update an existing supplement
    func updateSupplement(_ supplement: Supplement) async throws {
        try await context.perform { @Sendable [self, context] in
            let request = SupplementEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", supplement.id as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                throw AppError.coreDataFetchFailed
            }
            
            entity.name = supplement.name
            entity.dosage = supplement.dosage
            entity.unit = supplement.unit.rawValue
            entity.notes = supplement.notes
            entity.isActive = supplement.isActive
            entity.updatedAt = Date()
            entity.category = supplement.category?.rawValue
            entity.brand = supplement.brand
            
            // Update schedule
            if let scheduleEntity = entity.schedule {
                // Update existing schedule entity
                updateScheduleEntity(scheduleEntity, from: supplement.schedule)
            } else {
                // Create new schedule entity only if none exists
                entity.schedule = createScheduleEntity(from: supplement.schedule, in: context)
            }
            
            // Re-create doses for updated schedule
            createDosesForSupplement(entity, schedule: supplement.schedule, in: context)
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Fetch supplements from the persistent store
    func fetchSupplements(activeOnly: Bool = true) async throws -> [Supplement] {
        try await context.perform { @Sendable [context] in
            let request = SupplementEntity.fetchRequest()
            if activeOnly {
                request.predicate = NSPredicate(format: "isActive == %@", NSNumber(value: true))
            }
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { CoreDataConverter.convertToSupplement($0) }
        }
    }
    
    /// Delete a supplement by ID
    func deleteSupplement(_ id: UUID) async throws {
        try await context.perform { @Sendable [context] in
            let request = SupplementEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
            }
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Create a new schedule entity from a Schedule model
    nonisolated private func createScheduleEntity(from schedule: Schedule, in context: NSManagedObjectContext) -> ScheduleEntity {
        let scheduleEntity = ScheduleEntity(context: context)
        scheduleEntity.id = UUID()
        updateScheduleEntity(scheduleEntity, from: schedule)
        return scheduleEntity
    }
    
    /// Update an existing schedule entity with data from a Schedule model
    nonisolated private func updateScheduleEntity(_ entity: ScheduleEntity, from schedule: Schedule) {
        entity.frequency = schedule.frequency.rawValue
        entity.timePeriods = schedule.timePeriods.map { $0.rawValue } as NSArray
        entity.customTimes = schedule.customTimes as NSArray
        entity.startDate = schedule.startDate
        entity.endDate = schedule.endDate
        entity.activeDays = Array(schedule.activeDays) as NSArray
    }
    
    /// Pre-create dose records for all scheduled times
    nonisolated private func createDosesForSupplement(_ supplementEntity: SupplementEntity, schedule: Schedule, in context: NSManagedObjectContext) {
        // Delete existing doses first to avoid duplicates
        if let existingDoses = supplementEntity.doses as? Set<DoseEntity> {
            existingDoses.forEach { context.delete($0) }
        }
        
        // Create doses for today
        let today = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: today)
        
        // Create doses for today if it's scheduled
        if schedule.isScheduledForDate(today) {
            let todaysDoses = schedule.dosesForDate(today)
            
            for scheduledDose in todaysDoses {
                let doseEntity = DoseEntity(context: context)
                doseEntity.id = UUID()
                doseEntity.supplement = supplementEntity
                doseEntity.scheduledTime = scheduledDose.time
                doseEntity.period = scheduledDose.period.rawValue
                doseEntity.isTaken = false
                doseEntity.takenAt = nil
                doseEntity.notes = nil
                
                #if DEBUG
                print("📊 Created dose for \(supplementEntity.name ?? "Unknown") at \(scheduledDose.time) for today")
                #endif
            }
        }
        
        // Also create doses for the next 7 days to ensure continuity
        for dayOffset in 1...7 {
            if let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) {
                if schedule.isScheduledForDate(futureDate) {
                    let futureDoses = schedule.dosesForDate(futureDate)
                    
                    for scheduledDose in futureDoses {
                        let doseEntity = DoseEntity(context: context)
                        doseEntity.id = UUID()
                        doseEntity.supplement = supplementEntity
                        doseEntity.scheduledTime = scheduledDose.time
                        doseEntity.period = scheduledDose.period.rawValue
                        doseEntity.isTaken = false
                        doseEntity.takenAt = nil
                        doseEntity.notes = nil
                    }
                }
            }
        }
    }
}

// MARK: - Notifications
@available(iOS 18.0, *)
extension Notification.Name {
    static let lowStorageWarning = Notification.Name("com.healthguide.lowStorageWarning")
    static let coreDataDidSave = Notification.Name("coreDataDidSave")
}
