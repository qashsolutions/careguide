//
//  SupplementEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension SupplementEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SupplementEntity> {
        return NSFetchRequest<SupplementEntity>(entityName: "SupplementEntity")
    }

    @NSManaged public var brand: String?
    @NSManaged public var category: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var dosage: String?
    @NSManaged public var id: UUID?
    @NSManaged public var interactions: String?
    @NSManaged public var isActive: Bool
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var purpose: String?
    @NSManaged public var quantity: Int32
    @NSManaged public var unit: String?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var doses: NSSet?
    @NSManaged public var schedule: ScheduleEntity?

}

// MARK: Generated accessors for doses
extension SupplementEntity {

    @objc(addDosesObject:)
    @NSManaged public func addToDoses(_ value: DoseEntity)

    @objc(removeDosesObject:)
    @NSManaged public func removeFromDoses(_ value: DoseEntity)

    @objc(addDoses:)
    @NSManaged public func addToDoses(_ values: NSSet)

    @objc(removeDoses:)
    @NSManaged public func removeFromDoses(_ values: NSSet)

}

extension SupplementEntity : Identifiable {

}
