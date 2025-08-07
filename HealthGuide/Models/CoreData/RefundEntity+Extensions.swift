//
//  RefundEntity+Extensions.swift
//  HealthGuide
//
//  Core Data extensions for refund tracking
//

import Foundation
import CoreData

@available(iOS 18.0, *)
extension RefundEntity {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.id = UUID().uuidString
        self.status = "pending"
        self.createdAt = Date()
        self.refundDate = Date()
        self.daysSinceSubscription = 0
    }
    
    // MARK: - Computed Properties
    
    var isProcessed: Bool {
        guard let status = status else { return false }
        return status == "succeeded" || status == "failed"
    }
    
    var refundPercentage: Double {
        guard let subscription = subscription,
              let originalAmount = subscription.priceAmount,
              let refundAmount = amount else { return 0 }
        
        let percentage = (refundAmount.doubleValue / originalAmount.doubleValue) * 100
        return percentage
    }
    
    // MARK: - Helper Methods
    
    static func fetchPendingRefunds(context: NSManagedObjectContext) -> [RefundEntity] {
        let request: NSFetchRequest<RefundEntity> = RefundEntity.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", "pending")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching pending refunds: \(error)")
            return []
        }
    }
    
    static func fetchRefundHistory(for subscriptionId: String, context: NSManagedObjectContext) -> [RefundEntity] {
        let request: NSFetchRequest<RefundEntity> = RefundEntity.fetchRequest()
        request.predicate = NSPredicate(format: "subscription.id == %@", subscriptionId)
        request.sortDescriptors = [NSSortDescriptor(key: "refundDate", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching refund history: \(error)")
            return []
        }
    }
    
    func markAsProcessed(succeeded: Bool) {
        self.status = succeeded ? "succeeded" : "failed"
        self.subscription?.updatedAt = Date()
    }
    
    func updateRefundAmount(_ newAmount: Decimal) {
        self.amount = NSDecimalNumber(decimal: newAmount)
        self.subscription?.updatedAt = Date()
    }
}