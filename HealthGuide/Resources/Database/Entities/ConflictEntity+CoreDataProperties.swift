//
//  ConflictEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension ConflictEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ConflictEntity> {
        return NSFetchRequest<ConflictEntity>(entityName: "ConflictEntity")
    }

    @NSManaged public var checkedAt: Date?
    @NSManaged public var checkedBy: String?
    @NSManaged public var conflictDescription: String?
    @NSManaged public var id: UUID?
    @NSManaged public var medicationA: String?
    @NSManaged public var medicationB: String?
    @NSManaged public var recommendation: String?
    @NSManaged public var severity: String?

}

extension ConflictEntity : Identifiable {

}
