//
//  ContactEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension ContactEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ContactEntity> {
        return NSFetchRequest<ContactEntity>(entityName: "ContactEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var category: String?
    @NSManaged public var phone: String?
    @NSManaged public var isPrimary: Bool
    @NSManaged public var notes: String?

}

extension ContactEntity : Identifiable {

}
