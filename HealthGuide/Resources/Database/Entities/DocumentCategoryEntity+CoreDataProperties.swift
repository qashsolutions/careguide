//
//  DocumentCategoryEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/7/25.
//
//

import Foundation
import CoreData


extension DocumentCategoryEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DocumentCategoryEntity> {
        return NSFetchRequest<DocumentCategoryEntity>(entityName: "DocumentCategoryEntity")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var documentCount: Int32
    @NSManaged public var iconName: String?
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var documents: NSSet?

}

// MARK: Generated accessors for documents
extension DocumentCategoryEntity {

    @objc(addDocumentsObject:)
    @NSManaged public func addToDocuments(_ value: DocumentEntity)

    @objc(removeDocumentsObject:)
    @NSManaged public func removeFromDocuments(_ value: DocumentEntity)

    @objc(addDocuments:)
    @NSManaged public func addToDocuments(_ values: NSSet)

    @objc(removeDocuments:)
    @NSManaged public func removeFromDocuments(_ values: NSSet)

}

extension DocumentCategoryEntity : Identifiable {

}
