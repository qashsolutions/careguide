//
//  DocumentEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/3/25.
//
//

import Foundation
import CoreData


extension DocumentEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DocumentEntity> {
        return NSFetchRequest<DocumentEntity>(entityName: "DocumentEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var fileType: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var filename: String?
    @NSManaged public var category: String?
    @NSManaged public var fileSize: Int64
    @NSManaged public var localPath: String?
    @NSManaged public var notes: String?
    @NSManaged public var categoryRelation: DocumentCategoryEntity?

}

extension DocumentEntity : Identifiable {

}
