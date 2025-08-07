//
//  AccessSessionEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/4/25.
//
//

import Foundation
import CoreData


extension AccessSessionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AccessSessionEntity> {
        return NSFetchRequest<AccessSessionEntity>(entityName: "AccessSessionEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var userId: String?
    @NSManaged public var sessionStartTime: Date?
    @NSManaged public var sessionEndTime: Date?
    @NSManaged public var accessDate: Date?
    @NSManaged public var isActive: Bool
    @NSManaged public var accessType: Bool
    @NSManaged public var featuresAccessed: String?
    @NSManaged public var actionCount: Int32
    @NSManaged public var medicationUpdatesCount: Int32
    @NSManaged public var documentsViewed: Int32
    @NSManaged public var deviceModel: String?
    @NSManaged public var appVersion: String?
    @NSManaged public var timeZone: String?
    @NSManaged public var sessionDurationSeconds: Int32
    @NSManaged public var previousSessionId: String?
    @NSManaged public var daysSinceFirstUse: Int32
    @NSManaged public var totalSessionsCount: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

}

extension AccessSessionEntity : Identifiable {

}
