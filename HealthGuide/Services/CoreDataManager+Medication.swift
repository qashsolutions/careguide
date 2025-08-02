//  CoreDataManager+Medication.swift
//  Medication-specific Core Data operations
//  Handles CRUD operations for medications with validation
import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Medication Operations
    
    /// Save a medication to the persistent store
    func saveMedication(_ medication: Medication) async throws {
        // Validate the medication
        try medication.validate()
        
        try await context.perform { @Sendable [self, context] in
            // Check frequency limit within the same transaction
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
                throw AppError.internalError("Unable to calculate tomorrow's date")
            }
            
            let countRequest = MedicationEntity.fetchRequest()
            countRequest.predicate = NSPredicate(
                format: "name == %@ AND isActive == %@ AND createdAt >= %@ AND createdAt < %@",
                medication.name, NSNumber(value: true), today as CVarArg, tomorrow as CVarArg
            )
            
            let todayCount = try context.count(for: countRequest)
            if todayCount >= Configuration.HealthLimits.maximumDailyFrequency {
                throw AppError.medicationLimitExceeded(
                    current: todayCount,
                    maximum: Configuration.HealthLimits.maximumDailyFrequency
                )
            }
            
            let entity = MedicationEntity(context: context)
            populateMedicationEntity(entity, from: medication, in: context)
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Update an existing medication
    func updateMedication(_ medication: Medication) async throws {
        try await context.perform { @Sendable [self, context] in
            let request = MedicationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", medication.id as CVarArg)
            
            guard let entity = try context.fetch(request).first else {
                throw AppError.coreDataFetchFailed
            }
            
            populateMedicationEntity(entity, from: medication, in: context)
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Fetch medications from the persistent store
    func fetchMedications(activeOnly: Bool = true) async throws -> [Medication] {
        try await context.perform { @Sendable [context] in
            let request = MedicationEntity.fetchRequest()
            if activeOnly {
                request.predicate = NSPredicate(format: "isActive == %@", NSNumber(value: true))
            }
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { CoreDataConverter.convertToMedication($0) }
        }
    }
    
    /// Get medications scheduled for the current time period
    func getCurrentMedications() async throws -> [Medication] {
        try await context.perform { @Sendable [context] in
            let now = Date()
            
            // Fetch medications that are active and have schedules for today
            let request = MedicationEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "isActive == %@ AND schedule != nil",
                NSNumber(value: true)
            )
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            
            let entities = try context.fetch(request)
            let medications = entities.compactMap { CoreDataConverter.convertToMedication($0) }
            
            // Filter for current medications in memory (more complex logic)
            return medications.filter { medication in
                medication.schedule.dosesForDate(now).contains { dose in
                    !dose.isTaken && dose.isCurrent
                }
            }
        }
    }
    
    /// Delete a medication by ID
    func deleteMedication(_ id: UUID) async throws {
        try await context.perform { @Sendable [context] in
            let request = MedicationEntity.fetchRequest()
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
    
    /// Populate medication entity with data from medication model
    nonisolated func populateMedicationEntity(_ entity: MedicationEntity, from medication: Medication, in context: NSManagedObjectContext) {
        entity.id = medication.id
        entity.name = medication.name
        entity.dosage = medication.dosage.isEmpty ? nil : medication.dosage
        entity.quantity = Int32(medication.quantity)
        entity.unit = medication.unit.rawValue
        entity.notes = medication.notes
        entity.isActive = medication.isActive
        entity.createdAt = entity.createdAt ?? medication.createdAt
        entity.updatedAt = Date()
        entity.category = medication.category?.rawValue
        entity.prescribedBy = medication.prescribedBy
        entity.prescriptionNumber = medication.prescriptionNumber
        entity.refillsRemaining = medication.refillsRemaining.map { Int32($0) } ?? 0
        entity.expirationDate = medication.expirationDate
        
        // Handle schedule
        if let scheduleEntity = entity.schedule {
            configureSchedule(scheduleEntity, from: medication)
        } else {
            let scheduleEntity = ScheduleEntity(context: context)
            scheduleEntity.id = UUID()
            configureSchedule(scheduleEntity, from: medication)
            entity.schedule = scheduleEntity
        }
        
        // Pre-create doses for scheduled days
        createDosesForMedication(entity, schedule: medication.schedule, in: context)
    }
    
    /// Configure schedule entity from medication schedule
    nonisolated func configureSchedule(_ scheduleEntity: ScheduleEntity, from medication: Medication) {
        scheduleEntity.frequency = medication.schedule.frequency.rawValue
        scheduleEntity.timePeriods = medication.schedule.timePeriods.map(\.rawValue) as NSArray
        scheduleEntity.customTimes = medication.schedule.customTimes as NSArray
        scheduleEntity.startDate = medication.schedule.startDate
        scheduleEntity.endDate = medication.schedule.endDate
        scheduleEntity.activeDays = Array(medication.schedule.activeDays) as NSArray
    }
    
    /// Pre-create dose records for all scheduled times
    nonisolated func createDosesForMedication(_ medicationEntity: MedicationEntity, schedule: Schedule, in context: NSManagedObjectContext) {
        // Delete existing doses first to avoid duplicates
        if let existingDoses = medicationEntity.doses as? Set<DoseEntity> {
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
                doseEntity.medication = medicationEntity
                doseEntity.scheduledTime = scheduledDose.time
                doseEntity.period = scheduledDose.period.rawValue
                doseEntity.isTaken = false
                doseEntity.takenAt = nil
                doseEntity.notes = nil
                
                #if DEBUG
                print("📊 Created dose for \(medicationEntity.name ?? "Unknown") at \(scheduledDose.time) for today")
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
                        doseEntity.medication = medicationEntity
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
