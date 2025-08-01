//
//  DoseEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension DoseEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DoseEntity> {
        return NSFetchRequest<DoseEntity>(entityName: "DoseEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var isTaken: Bool
    @NSManaged public var notes: String?
    @NSManaged public var period: String?
    @NSManaged public var scheduledTime: Date?
    @NSManaged public var takenAt: Date?
    @NSManaged public var diet: DietEntity?
    @NSManaged public var medication: MedicationEntity?
    @NSManaged public var supplement: SupplementEntity?

}

extension DoseEntity : Identifiable {

}
