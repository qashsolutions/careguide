//
//  GroupMemberEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension GroupMemberEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupMemberEntity> {
        return NSFetchRequest<GroupMemberEntity>(entityName: "GroupMemberEntity")
    }

    @NSManaged public var email: String?
    @NSManaged public var id: UUID?
    @NSManaged public var joinedAt: Date?
    @NSManaged public var lastActiveAt: Date?
    @NSManaged public var name: String?
    @NSManaged public var permissions: String?
    @NSManaged public var phoneNumber: String?
    @NSManaged public var profileColor: String?
    @NSManaged public var role: String?
    @NSManaged public var userID: UUID?
    @NSManaged public var group: CareGroupEntity?

}

extension GroupMemberEntity : Identifiable {

}
