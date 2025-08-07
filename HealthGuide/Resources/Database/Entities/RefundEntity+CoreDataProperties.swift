//
//  RefundEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/3/25.
//
//

import Foundation
import CoreData


extension RefundEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RefundEntity> {
        return NSFetchRequest<RefundEntity>(entityName: "RefundEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var reason: String?
    @NSManaged public var status: String?
    @NSManaged public var refundDate: Date?
    @NSManaged public var daysSinceSubscription: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var subscription: SubscriptionEntity?

}

extension RefundEntity : Identifiable {

}
