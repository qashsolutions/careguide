//
//  DietEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension DietEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DietEntity> {
        return NSFetchRequest<DietEntity>(entityName: "DietEntity")
    }

    @NSManaged public var calories: Int32
    @NSManaged public var category: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isActive: Bool
    @NSManaged public var mealType: String?
    @NSManaged public var name: String?
    @NSManaged public var notes: String?
    @NSManaged public var portion: String?
    @NSManaged public var restrictions: NSArray?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var doses: NSSet?
    @NSManaged public var schedule: ScheduleEntity?

}

// MARK: Generated accessors for doses
extension DietEntity {

    @objc(addDosesObject:)
    @NSManaged public func addToDoses(_ value: DoseEntity)

    @objc(removeDosesObject:)
    @NSManaged public func removeFromDoses(_ value: DoseEntity)

    @objc(addDoses:)
    @NSManaged public func addToDoses(_ values: NSSet)

    @objc(removeDoses:)
    @NSManaged public func removeFromDoses(_ values: NSSet)

}

extension DietEntity : Identifiable {

}
