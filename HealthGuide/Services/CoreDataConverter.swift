
//  CoreDataConverter.swift
//  HealthGuide

//  CoreDataConverter.swift
//  HealthGuide/Services/
//
//  Core Data entity to model conversions - Swift 6 optimized
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
final class CoreDataConverter {
    
    // MARK: - Medication Conversions
    
    static func convertToMedication(_ entity: MedicationEntity) -> Medication? {
        guard let id = entity.id,
              let name = entity.name else { return nil }
        
        // Handle optional dosage and unit with defaults
        let dosage = entity.dosage ?? ""
        let unitString = entity.unit ?? "tablet"
        let unit = Medication.DosageUnit(rawValue: unitString) ?? .tablet
        
        // Handle optional schedule
        let schedule = convertToSchedule(entity.schedule) ?? Schedule()
        
        return Medication(
            id: id,
            name: name,
            dosage: dosage,
            quantity: Int(entity.quantity),
            unit: unit,
            notes: entity.notes,
            schedule: schedule,
            isActive: entity.isActive,
            category: entity.category.flatMap { Medication.MedicationCategory(rawValue: $0) },
            prescribedBy: entity.prescribedBy,
            prescriptionNumber: entity.prescriptionNumber,
            refillsRemaining: entity.refillsRemaining > 0 ? Int(entity.refillsRemaining) : nil,
            expirationDate: entity.expirationDate
        )
    }
    
    // MARK: - Supplement Conversions
    
    static func convertToSupplement(_ entity: SupplementEntity) -> Supplement? {
        guard let id = entity.id,
              let name = entity.name else { return nil }
        
        // Handle optional dosage and unit with defaults
        let dosage = entity.dosage ?? ""
        let unitString = entity.unit ?? "tablet"
        let unit = Supplement.SupplementUnit(rawValue: unitString) ?? .tablet
        
        // Handle optional schedule
        let schedule = convertToSchedule(entity.schedule) ?? Schedule()
        
        return Supplement(
            id: id,
            name: name,
            dosage: dosage,
            unit: unit,
            notes: entity.notes,
            schedule: schedule,
            isActive: entity.isActive,
            category: entity.category.flatMap { Supplement.SupplementCategory(rawValue: $0) },
            brand: entity.brand
        )
    }
    
    // MARK: - Diet Conversions
    
    static func convertToDiet(_ entity: DietEntity) -> Diet? {
        guard let id = entity.id,
              let name = entity.name,
              let portion = entity.portion,
              let schedule = convertToSchedule(entity.schedule) else { return nil }
        
        // Cache type conversions
        let restrictionStrings = (entity.restrictions as? [String]) ?? []
        let restrictions = Set(restrictionStrings.compactMap { Diet.DietaryRestriction(rawValue: $0) })
        let category = entity.category.flatMap { Diet.DietCategory(rawValue: $0) }
        let mealType = entity.mealType.flatMap { Diet.MealType(rawValue: $0) }
        let calories = entity.calories > 0 ? Int(entity.calories) : nil
        
        return Diet(
            id: id,
            name: name,
            portion: portion,
            notes: entity.notes,
            schedule: schedule,
            isActive: entity.isActive,
            category: category,
            calories: calories,
            restrictions: restrictions,
            mealType: mealType
        )
    }
    
    // MARK: - Schedule Conversions
    
    static func convertToSchedule(_ entity: ScheduleEntity?) -> Schedule? {
        guard let entity = entity,
              let frequencyString = entity.frequency,
              let frequency = Schedule.Frequency(rawValue: frequencyString) else { return nil }
        
        let timePeriods = (entity.timePeriods as? [String])?.compactMap { TimePeriod(rawValue: $0) } ?? []
        let customTimes = (entity.customTimes as? [Date]) ?? []
        let activeDays = Set((entity.activeDays as? [Date]) ?? [])
        
        return Schedule(
            frequency: frequency,
            timePeriods: timePeriods,
            customTimes: customTimes,
            startDate: entity.startDate ?? Date(),
            endDate: entity.endDate,
            activeDays: activeDays
        )
    }
}
