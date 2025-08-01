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
}

// MARK: - Notifications
@available(iOS 18.0, *)
extension Notification.Name {
    static let lowStorageWarning = Notification.Name("com.healthguide.lowStorageWarning")
    static let coreDataDidSave = Notification.Name("com.healthguide.coreDataDidSave")
}
