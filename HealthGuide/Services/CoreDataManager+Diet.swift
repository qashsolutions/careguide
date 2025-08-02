//
//  CoreDataManager+Diet.swift
//  HealthGuide
//
//  Diet-specific Core Data operations
//  Handles CRUD operations for diet items with validation
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Diet Operations
    
    /// Save a diet item to the persistent store
    func saveDiet(_ diet: Diet) async throws {
        // Validate the diet item
        try diet.validate()
        
        try await context.perform { @Sendable [self, context] in
            let entity = DietEntity(context: context)
            entity.id = diet.id
            entity.name = diet.name
            entity.portion = diet.portion
            entity.notes = diet.notes
            entity.isActive = diet.isActive
            entity.createdAt = diet.createdAt
            entity.updatedAt = Date()
            entity.category = diet.category?.rawValue
            entity.calories = diet.calories.map { Int32($0) } ?? 0
            entity.restrictions = diet.restrictions.map { $0.rawValue } as NSArray
            entity.mealType = diet.mealType?.rawValue
            
            // Create schedule
            entity.schedule = createScheduleEntity(from: diet.schedule, in: context)
            
            // Pre-create doses for scheduled days
            createDosesForDiet(entity, schedule: diet.schedule, in: context)
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Update an existing diet item
    func updateDiet(_ diet: Diet) async throws {
        try await context.perform { @Sendable [self, context] in
            let request = DietEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", diet.id as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                throw AppError.coreDataFetchFailed
            }
            
            entity.name = diet.name
            entity.portion = diet.portion
            entity.notes = diet.notes
            entity.isActive = diet.isActive
            entity.updatedAt = Date()
            entity.category = diet.category?.rawValue
            entity.calories = diet.calories.map { Int32($0) } ?? 0
            entity.restrictions = diet.restrictions.map { $0.rawValue } as NSArray
            entity.mealType = diet.mealType?.rawValue
            
            // Update schedule
            if let scheduleEntity = entity.schedule {
                // Update existing schedule entity
                updateScheduleEntity(scheduleEntity, from: diet.schedule)
            } else {
                // Create new schedule entity only if none exists
                entity.schedule = createScheduleEntity(from: diet.schedule, in: context)
            }
            
            // Re-create doses for updated schedule
            createDosesForDiet(entity, schedule: diet.schedule, in: context)
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Fetch diet items from the persistent store
    func fetchDietItems(activeOnly: Bool = true) async throws -> [Diet] {
        try await context.perform { @Sendable [context] in
            let request = DietEntity.fetchRequest()
            if activeOnly {
                request.predicate = NSPredicate(format: "isActive == %@", NSNumber(value: true))
            }
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { CoreDataConverter.convertToDiet($0) }
        }
    }
    
    /// Delete a diet item by ID
    func deleteDiet(_ id: UUID) async throws {
        try await context.perform { @Sendable [context] in
            let request = DietEntity.fetchRequest()
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
    nonisolated private func createDosesForDiet(_ dietEntity: DietEntity, schedule: Schedule, in context: NSManagedObjectContext) {
        // Delete existing doses first to avoid duplicates
        if let existingDoses = dietEntity.doses as? Set<DoseEntity> {
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
                doseEntity.diet = dietEntity
                doseEntity.scheduledTime = scheduledDose.time
                doseEntity.period = scheduledDose.period.rawValue
                doseEntity.isTaken = false
                doseEntity.takenAt = nil
                doseEntity.notes = nil
                
                #if DEBUG
                print("📊 Created dose for \(dietEntity.name ?? "Unknown") at \(scheduledDose.time) for today")
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
                        doseEntity.diet = dietEntity
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
