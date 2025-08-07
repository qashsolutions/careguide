//
//  PaymentEntity+Extensions.swift
//  HealthGuide
//
//  Core Data extensions for payment tracking
//

import Foundation
import CoreData

@available(iOS 18.0, *)
extension PaymentEntity {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.id = UUID().uuidString
        self.status = "pending"
        self.createdAt = Date()
        self.paymentDate = Date()
    }
    
    // MARK: - Computed Properties
    
    var isSuccessful: Bool {
        return status == "succeeded"
    }
    
    var isFailed: Bool {
        return status == "failed"
    }
    
    var isPending: Bool {
        return status == "pending"
    }
    
    // MARK: - Helper Methods
    
    static func fetchPaymentHistory(for subscriptionId: String, context: NSManagedObjectContext) -> [PaymentEntity] {
        let request: NSFetchRequest<PaymentEntity> = PaymentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "subscription.id == %@", subscriptionId)
        request.sortDescriptors = [NSSortDescriptor(key: "paymentDate", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching payment history: \(error)")
            return []
        }
    }
    
    static func fetchSuccessfulPayments(context: NSManagedObjectContext) -> [PaymentEntity] {
        let request: NSFetchRequest<PaymentEntity> = PaymentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", "succeeded")
        request.sortDescriptors = [NSSortDescriptor(key: "paymentDate", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching successful payments: \(error)")
            return []
        }
    }
    
    static func calculateTotalRevenue(context: NSManagedObjectContext) -> Decimal {
        let request: NSFetchRequest<PaymentEntity> = PaymentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", "succeeded")
        
        do {
            let payments = try context.fetch(request)
            let total = payments.compactMap { $0.amount?.decimalValue }.reduce(0, +)
            return total
        } catch {
            print("Error calculating total revenue: \(error)")
            return 0
        }
    }
    
    func markAsSucceeded(invoiceId: String? = nil, receiptUrl: String? = nil) {
        self.status = "succeeded"
        self.invoiceId = invoiceId
        self.receiptUrl = receiptUrl
        self.subscription?.updatedAt = Date()
    }
    
    func markAsFailed() {
        self.status = "failed"
        self.subscription?.updatedAt = Date()
    }
    
    static func createPayment(
        paymentId: String,
        amount: Decimal,
        subscription: SubscriptionEntity,
        context: NSManagedObjectContext
    ) -> PaymentEntity {
        let payment = PaymentEntity(context: context)
        payment.id = paymentId
        payment.amount = NSDecimalNumber(decimal: amount)
        payment.status = "pending"
        payment.paymentDate = Date()
        payment.subscription = subscription
        subscription.addToPayments(payment)
        
        return payment
    }
}