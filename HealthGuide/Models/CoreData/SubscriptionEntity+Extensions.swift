//
//  SubscriptionEntity+Extensions.swift
//  HealthGuide
//
//  Core Data extensions for subscription tracking
//

import Foundation
import CoreData

@available(iOS 18.0, *)
extension SubscriptionEntity {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.id = UUID().uuidString
        self.status = "none"
        self.paymentMethod = "apple_pay"
        self.currency = "USD"
        self.priceAmount = NSDecimalNumber(decimal: 8.99)
        self.hasUsedRefund = false
        self.autoRenew = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Computed Properties
    
    var isActive: Bool {
        guard let status = status else { return false }
        return status == "active" || status == "trial"
    }
    
    var isInRefundPeriod: Bool {
        guard let startDate = startDate else { return false }
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return daysSinceStart >= 8 && daysSinceStart <= 14
    }
    
    var daysInSubscription: Int {
        guard let startDate = startDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }
    
    var refundsArray: [RefundEntity] {
        let set = refunds as? Set<RefundEntity> ?? []
        return set.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
    }
    
    var paymentsArray: [PaymentEntity] {
        let set = payments as? Set<PaymentEntity> ?? []
        return set.sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
    }
    
    // MARK: - Helper Methods
    
    static func fetchActiveSubscription(context: NSManagedObjectContext) -> SubscriptionEntity? {
        let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "status IN %@", ["active", "trial"])
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching active subscription: \(error)")
            return nil
        }
    }
    
    static func createOrUpdate(
        subscriptionId: String,
        customerId: String,
        email: String,
        status: String,
        paymentMethod: String,
        context: NSManagedObjectContext
    ) -> SubscriptionEntity {
        
        let request: NSFetchRequest<SubscriptionEntity> = SubscriptionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", subscriptionId)
        request.fetchLimit = 1
        
        let subscription: SubscriptionEntity
        if let existing = try? context.fetch(request).first {
            subscription = existing
        } else {
            subscription = SubscriptionEntity(context: context)
            subscription.id = subscriptionId
        }
        
        subscription.customerId = customerId
        subscription.userEmail = email
        subscription.status = status
        subscription.paymentMethod = paymentMethod
        subscription.updatedAt = Date()
        
        return subscription
    }
    
    func recordPayment(paymentId: String, amount: Decimal, status: String, context: NSManagedObjectContext) {
        let payment = PaymentEntity(context: context)
        payment.id = paymentId
        payment.amount = NSDecimalNumber(decimal: amount)
        payment.status = status
        payment.paymentDate = Date()
        payment.subscription = self
        self.addToPayments(payment)
    }
    
    func processRefund(amount: Decimal, reason: String, context: NSManagedObjectContext) -> RefundEntity? {
        guard !hasUsedRefund else { return nil }
        guard isInRefundPeriod else { return nil }
        
        let refund = RefundEntity(context: context)
        refund.id = UUID().uuidString
        refund.amount = NSDecimalNumber(decimal: amount * 0.5)
        refund.reason = reason
        refund.status = "pending"
        refund.refundDate = Date()
        refund.daysSinceSubscription = Int32(daysInSubscription)
        refund.subscription = self
        self.addToRefunds(refund)
        
        self.hasUsedRefund = true
        self.updatedAt = Date()
        
        return refund
    }
}