//
//  CoreDataOptimizations.swift
//  HealthGuide
//
//  Performance optimizations for Core Data operations
//

import Foundation
import CoreData

@available(iOS 18.0, *)
struct CoreDataOptimizer {
    
    /// Configure fetch request for optimal performance
    static func optimizeFetchRequest<T: NSManagedObject>(_ request: NSFetchRequest<T>) {
        // Limit results to reduce memory
        if request.fetchLimit == 0 {
            request.fetchLimit = 100
        }
        
        // Use batch fetching for large result sets
        request.fetchBatchSize = 20
        
        // Don't fetch more than needed
        request.includesSubentities = false
        
        // Return faults to reduce memory
        request.returnsObjectsAsFaults = true
        
        // Only fetch properties we need
        request.includesPendingChanges = false
    }
    
    /// Configure for counting only (no object fetching)
    static func optimizeForCounting<T: NSManagedObject>(_ request: NSFetchRequest<T>) {
        request.resultType = .countResultType
        request.includesSubentities = false
        request.includesPendingChanges = false
    }
    
    /// Configure for lightweight fetching
    static func optimizeForLightweight<T: NSManagedObject>(_ request: NSFetchRequest<T>) {
        request.fetchBatchSize = 10
        request.returnsObjectsAsFaults = true
        request.relationshipKeyPathsForPrefetching = []
    }
}

@available(iOS 18.0, *)
extension NSManagedObjectContext {
    
    /// Perform batch delete for better performance
    func performBatchDelete(for entity: String, predicate: NSPredicate? = nil) async throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
        fetchRequest.predicate = predicate
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        try await perform { [weak self] in
            guard let self = self else { return }
            
            let result = try self.execute(deleteRequest) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: changes,
                    into: [self]
                )
            }
        }
    }
    
    /// Reset context to free memory
    func freeMemory() {
        reset()
        processPendingChanges()
        undoManager = nil
        stalenessInterval = 30.0
    }
}

@available(iOS 18.0, *)
extension PersistenceController {
    
    /// Create optimized fetch request for entity
    func createOptimizedFetchRequest<T: NSManagedObject>(for entity: T.Type) -> NSFetchRequest<T> {
        let request = NSFetchRequest<T>(entityName: String(describing: entity))
        CoreDataOptimizer.optimizeFetchRequest(request)
        return request
    }
    
    /// Fetch with automatic optimization
    func optimizedFetch<T: NSManagedObject>(_ entity: T.Type, 
                                            predicate: NSPredicate? = nil,
                                            sortDescriptors: [NSSortDescriptor]? = nil,
                                            limit: Int? = nil) async throws -> [T] {
        let request = createOptimizedFetchRequest(for: entity)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        if let limit = limit {
            request.fetchLimit = limit
        }
        
        return try await container.viewContext.perform {
            try self.container.viewContext.fetch(request)
        }
    }
}