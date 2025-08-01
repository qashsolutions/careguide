//
//  CoreDataManager+Schedule.swift
//  HealthGuide
//
//  Schedule and dose tracking operations
//  Shared by medications, supplements, and diet items
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Schedule Operations
    
    /// Save a schedule to the persistent store
    func saveSchedule(_ schedule: Schedule) async throws -> UUID {
        await context.perform { @Sendable [context] in
            let entity = ScheduleEntity(context: context)
            let scheduleId = UUID()
            entity.id = scheduleId
            entity.frequency = schedule.frequency.rawValue
            entity.timePeriods = schedule.timePeriods.map { $0.rawValue } as NSArray
            entity.customTimes = schedule.customTimes as NSArray
            entity.startDate = schedule.startDate
            entity.endDate = schedule.endDate
            entity.activeDays = Array(schedule.activeDays) as NSArray
            
            return scheduleId
        }
    }
    
    
    // MARK: - Dose Tracking
    
    /// Mark a dose as taken using relationships
    func markDoseTaken(forSupplementId supplementId: UUID, doseId: UUID, takenAt: Date = Date()) async throws {
        try await context.perform { @Sendable [context] in
            // Fetch the supplement entity
            let supplementRequest = SupplementEntity.fetchRequest()
            supplementRequest.predicate = NSPredicate(format: "id == %@", supplementId as CVarArg)
            guard let supplement = try context.fetch(supplementRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            let request = DoseEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", doseId as CVarArg)
            
            if let dose = try context.fetch(request).first {
                dose.isTaken = true
                dose.takenAt = takenAt
            } else {
                // Create new dose record if not found
                let doseEntity = DoseEntity(context: context)
                doseEntity.id = doseId
                doseEntity.supplement = supplement
                doseEntity.isTaken = true
                doseEntity.takenAt = takenAt
                doseEntity.scheduledTime = Date()
                doseEntity.period = "morning" // Default period
            }
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Mark a dose as taken for medication using relationships
    func markDoseTaken(forMedicationId medicationId: UUID, doseId: UUID, takenAt: Date = Date()) async throws {
        try await context.perform { @Sendable [context] in
            // Fetch the medication entity
            let medicationRequest = MedicationEntity.fetchRequest()
            medicationRequest.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
            guard let medication = try context.fetch(medicationRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            let request = DoseEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", doseId as CVarArg)
            
            if let dose = try context.fetch(request).first {
                dose.isTaken = true
                dose.takenAt = takenAt
            } else {
                // Create new dose record if not found
                let doseEntity = DoseEntity(context: context)
                doseEntity.id = doseId
                doseEntity.medication = medication
                doseEntity.isTaken = true
                doseEntity.takenAt = takenAt
                doseEntity.scheduledTime = Date()
                doseEntity.period = "morning" // Default period
            }
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Mark a dose as taken for diet using relationships
    func markDoseTaken(forDietId dietId: UUID, doseId: UUID, takenAt: Date = Date()) async throws {
        try await context.perform { @Sendable [context] in
            // Fetch the diet entity
            let dietRequest = DietEntity.fetchRequest()
            dietRequest.predicate = NSPredicate(format: "id == %@", dietId as CVarArg)
            guard let diet = try context.fetch(dietRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            let request = DoseEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", doseId as CVarArg)
            
            if let dose = try context.fetch(request).first {
                dose.isTaken = true
                dose.takenAt = takenAt
            } else {
                // Create new dose record if not found
                let doseEntity = DoseEntity(context: context)
                doseEntity.id = doseId
                doseEntity.diet = diet
                doseEntity.isTaken = true
                doseEntity.takenAt = takenAt
                doseEntity.scheduledTime = Date()
                doseEntity.period = "breakfast" // Default period
            }
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Get dose history for a supplement
    func getDoseHistory(
        forSupplementId supplementId: UUID,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> [DoseRecord] {
        try await context.perform { @Sendable [self, context] in
            // First fetch the supplement
            let supplementRequest = SupplementEntity.fetchRequest()
            supplementRequest.predicate = NSPredicate(format: "id == %@", supplementId as CVarArg)
            guard let supplement = try context.fetch(supplementRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            let request = DoseEntity.fetchRequest()
            
            var predicates = [NSPredicate(format: "supplement == %@", supplement)]
            
            if let startDate = startDate {
                predicates.append(NSPredicate(format: "takenAt >= %@", startDate as CVarArg))
            }
            
            if let endDate = endDate {
                predicates.append(NSPredicate(format: "takenAt <= %@", endDate as CVarArg))
            }
            
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "takenAt", ascending: false)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { convertToDoseRecord($0) }
        }
    }
    
    /// Get dose history for a medication
    func getDoseHistory(
        forMedicationId medicationId: UUID,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> [DoseRecord] {
        try await context.perform { @Sendable [self, context] in
            // First fetch the medication
            let medicationRequest = MedicationEntity.fetchRequest()
            medicationRequest.predicate = NSPredicate(format: "id == %@", medicationId as CVarArg)
            guard let medication = try context.fetch(medicationRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            let request = DoseEntity.fetchRequest()
            
            var predicates = [NSPredicate(format: "medication == %@", medication)]
            
            if let startDate = startDate {
                predicates.append(NSPredicate(format: "takenAt >= %@", startDate as CVarArg))
            }
            
            if let endDate = endDate {
                predicates.append(NSPredicate(format: "takenAt <= %@", endDate as CVarArg))
            }
            
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "takenAt", ascending: false)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { convertToDoseRecord($0) }
        }
    }
    
    /// Get dose history for a diet item
    func getDoseHistory(
        forDietId dietId: UUID,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> [DoseRecord] {
        try await context.perform { @Sendable [self, context] in
            // First fetch the diet
            let dietRequest = DietEntity.fetchRequest()
            dietRequest.predicate = NSPredicate(format: "id == %@", dietId as CVarArg)
            guard let diet = try context.fetch(dietRequest).first else {
                throw AppError.coreDataFetchFailed
            }
            
            let request = DoseEntity.fetchRequest()
            
            var predicates = [NSPredicate(format: "diet == %@", diet)]
            
            if let startDate = startDate {
                predicates.append(NSPredicate(format: "takenAt >= %@", startDate as CVarArg))
            }
            
            if let endDate = endDate {
                predicates.append(NSPredicate(format: "takenAt <= %@", endDate as CVarArg))
            }
            
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            request.sortDescriptors = [NSSortDescriptor(key: "takenAt", ascending: false)]
            
            let entities = try context.fetch(request)
            return entities.compactMap { convertToDoseRecord($0) }
        }
    }
    
    /// Get adherence statistics for a supplement
    func getAdherenceStats(
        forSupplementId supplementId: UUID,
        days: Int = 30
    ) async throws -> AdherenceStats {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let doses = try await getDoseHistory(forSupplementId: supplementId, startDate: startDate)
        
        let totalScheduled = doses.count
        let taken = doses.filter { $0.isTaken }.count
        let missed = totalScheduled - taken
        
        let adherenceRate = totalScheduled > 0 ? Double(taken) / Double(totalScheduled) : 0.0
        
        return AdherenceStats(
            totalDoses: totalScheduled,
            takenDoses: taken,
            missedDoses: missed,
            adherenceRate: adherenceRate,
            period: days
        )
    }
    
    // MARK: - Private Helpers
    
    nonisolated private func convertToDoseRecord(_ entity: DoseEntity) -> DoseRecord? {
        guard let id = entity.id else { return nil }
        
        // Determine which entity this dose belongs to
        let itemId: UUID?
        let itemType: String
        
        if let supplement = entity.supplement {
            itemId = supplement.id
            itemType = "supplement"
        } else if let medication = entity.medication {
            itemId = medication.id
            itemType = "medication"
        } else if let diet = entity.diet {
            itemId = diet.id
            itemType = "diet"
        } else {
            return nil
        }
        
        guard let actualItemId = itemId else { return nil }
        
        return DoseRecord(
            id: id,
            itemId: actualItemId,
            itemType: itemType,
            scheduledTime: entity.scheduledTime ?? Date(),
            takenAt: entity.takenAt,
            isTaken: entity.isTaken,
            period: entity.period ?? "unknown",
            notes: entity.notes
        )
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, *)
struct DoseRecord {
    let id: UUID
    let itemId: UUID
    let itemType: String // "supplement", "medication", or "diet"
    let scheduledTime: Date
    let takenAt: Date?
    let isTaken: Bool
    let period: String
    let notes: String?
}

@available(iOS 18.0, *)
struct AdherenceStats {
    let totalDoses: Int
    let takenDoses: Int
    let missedDoses: Int
    let adherenceRate: Double
    let period: Int // in days
    
    var adherencePercentage: Int {
        Int(adherenceRate * 100)
    }
    
    var isGoodAdherence: Bool {
        adherenceRate >= 0.8 // 80% or higher
    }
}
