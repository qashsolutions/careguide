//
//  CareGroupEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/31/25.
//
//

import Foundation
import CoreData


extension CareGroupEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CareGroupEntity> {
        return NSFetchRequest<CareGroupEntity>(entityName: "CareGroupEntity")
    }

    @NSManaged public var adminUserID: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var inviteCode: String?
    @NSManaged public var inviteCodeExpiry: Date?
    @NSManaged public var name: String?
    @NSManaged public var settings: NSDictionary?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var members: NSSet?

}

// MARK: Generated accessors for members
extension CareGroupEntity {

    @objc(addMembersObject:)
    @NSManaged public func addToMembers(_ value: GroupMemberEntity)

    @objc(removeMembersObject:)
    @NSManaged public func removeFromMembers(_ value: GroupMemberEntity)

    @objc(addMembers:)
    @NSManaged public func addToMembers(_ values: NSSet)

    @objc(removeMembers:)
    @NSManaged public func removeFromMembers(_ values: NSSet)

}

extension CareGroupEntity : Identifiable {

}
