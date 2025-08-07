//
//  PaymentEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/3/25.
//
//

import Foundation
import CoreData


extension PaymentEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PaymentEntity> {
        return NSFetchRequest<PaymentEntity>(entityName: "PaymentEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var status: String?
    @NSManaged public var paymentDate: Date?
    @NSManaged public var invoiceId: String?
    @NSManaged public var receiptUrl: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var subscription: SubscriptionEntity?

}

extension PaymentEntity : Identifiable {

}
