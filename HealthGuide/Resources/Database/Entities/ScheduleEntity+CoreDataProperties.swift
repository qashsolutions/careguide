//
//  ScheduleEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension ScheduleEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScheduleEntity> {
        return NSFetchRequest<ScheduleEntity>(entityName: "ScheduleEntity")
    }

    @NSManaged public var activeDays: NSArray?
    @NSManaged public var customTimes: NSArray?
    @NSManaged public var endDate: Date?
    @NSManaged public var frequency: String?
    @NSManaged public var id: UUID?
    @NSManaged public var startDate: Date?
    @NSManaged public var timePeriods: NSArray?
    @NSManaged public var diet: DietEntity?
    @NSManaged public var medication: MedicationEntity?
    @NSManaged public var supplement: SupplementEntity?

}

extension ScheduleEntity : Identifiable {

}
