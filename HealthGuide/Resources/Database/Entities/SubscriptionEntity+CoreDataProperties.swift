//
//  SubscriptionEntity+CoreDataProperties.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 8/3/25.
//
//

import Foundation
import CoreData


extension SubscriptionEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SubscriptionEntity> {
        return NSFetchRequest<SubscriptionEntity>(entityName: "SubscriptionEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var customerId: String?
    @NSManaged public var status: String?
    @NSManaged public var paymentMethod: String?
    @NSManaged public var startDate: Date?
    @NSManaged public var trialEndDate: Date?
    @NSManaged public var currentPeriodEnd: Date?
    @NSManaged public var cancellationDate: Date?
    @NSManaged public var autoRenew: Bool
    @NSManaged public var priceAmount: NSDecimalNumber?
    @NSManaged public var currency: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var userEmail: String?
    @NSManaged public var userPhone: String?
    @NSManaged public var hasUsedRefund: Bool
    @NSManaged public var refunds: NSSet?
    @NSManaged public var payments: NSSet?

}

// MARK: Generated accessors for refunds
extension SubscriptionEntity {

    @objc(addRefundsObject:)
    @NSManaged public func addToRefunds(_ value: RefundEntity)

    @objc(removeRefundsObject:)
    @NSManaged public func removeFromRefunds(_ value: RefundEntity)

    @objc(addRefunds:)
    @NSManaged public func addToRefunds(_ values: NSSet)

    @objc(removeRefunds:)
    @NSManaged public func removeFromRefunds(_ values: NSSet)

}

// MARK: Generated accessors for payments
extension SubscriptionEntity {

    @objc(addPaymentsObject:)
    @NSManaged public func addToPayments(_ value: PaymentEntity)

    @objc(removePaymentsObject:)
    @NSManaged public func removeFromPayments(_ value: PaymentEntity)

    @objc(addPayments:)
    @NSManaged public func addToPayments(_ values: NSSet)

    @objc(removePayments:)
    @NSManaged public func removeFromPayments(_ values: NSSet)

}

extension SubscriptionEntity : Identifiable {

}
