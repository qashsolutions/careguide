//
//  MedicationEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension MedicationEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MedicationEntity> {
        return NSFetchRequest<MedicationEntity>(entityName: "MedicationEntity")
    }

    @NSManaged public var category: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var dosage: String?
    @NSManaged public var expirationDate: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isActive: Bool
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var prescribedBy: String?
    @NSManaged public var prescriptionNumber: String?
    @NSManaged public var quantity: Int32
    @NSManaged public var refillsRemaining: Int32
    @NSManaged public var unit: String?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var doses: NSSet?
    @NSManaged public var schedule: ScheduleEntity?

}

// MARK: Generated accessors for doses
extension MedicationEntity {

    @objc(addDosesObject:)
    @NSManaged public func addToDoses(_ value: DoseEntity)

    @objc(removeDosesObject:)
    @NSManaged public func removeFromDoses(_ value: DoseEntity)

    @objc(addDoses:)
    @NSManaged public func addToDoses(_ values: NSSet)

    @objc(removeDoses:)
    @NSManaged public func removeFromDoses(_ values: NSSet)

}

extension MedicationEntity : Identifiable {

}
