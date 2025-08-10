//
//  CareMemoEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/10/25.
//
//

import Foundation
import CoreData


extension CareMemoEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CareMemoEntity> {
        return NSFetchRequest<CareMemoEntity>(entityName: "CareMemoEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var audioFileURL: String?
    @NSManaged public var duration: Double
    @NSManaged public var recordedAt: Date?
    @NSManaged public var transcription: String?
    @NSManaged public var priority: String?
    @NSManaged public var relatedMedicationIds: Data?
    @NSManaged public var title: String?

}

extension CareMemoEntity : Identifiable {

}
