//
//  CoreDataManager.swift
//  HealthGuide/Services/
//
//  Core data persistence layer - Swift 6 compliant actor implementation
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
actor CoreDataManager {
    
    // MARK: - Singleton
    static let shared = CoreDataManager()
    
    // MARK: - Properties
    private let persistenceController = PersistenceController.shared
    
    // Actor-isolated background context for thread safety
    internal lazy var context: NSManagedObjectContext = {
        let ctx = persistenceController.container.newBackgroundContext()
        ctx.automaticallyMergesChangesFromParent = true
        return ctx
    }()
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Core Operations
    
    /// Save changes to the persistent store
    func save() async throws {
        try await context.perform { @Sendable [context] in
            guard context.hasChanges else { return }
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Delete a managed object
    func delete(object: NSManagedObject) async throws {
        try await context.perform { @Sendable [context] in
            context.delete(object)
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Perform a batch delete operation
    func batchDelete<T: NSManagedObject>(
        entityType: T.Type,
        predicateFormat: String? = nil,
        arguments: [any Sendable]? = nil
    ) async throws {
        let entityName = String(describing: entityType)
        let safeArguments = arguments ?? []
        
        try await context.perform { @Sendable [context] in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(
                entityName: entityName
            )
            
            if let format = predicateFormat {
                fetchRequest.predicate = NSPredicate(format: format, argumentArray: safeArguments)
            }
            
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            guard let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
                  let objectIDs = result.result as? [NSManagedObjectID] else {
                throw CoreDataError.batchDeleteFailed
            }
            
            // Merge changes to keep contexts in sync
            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: changes,
                into: [context]
            )
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    /// Reset all data in the database
    func resetAllData() async throws {
        let entityNames = persistenceController.container.managedObjectModel.entities.compactMap { $0.name }
        
        try await context.perform { @Sendable [context] in
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                try context.execute(deleteRequest)
            }
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .coreDataDidSave, object: nil)
        }
    }
    
    // MARK: - Context Management
    
    /// Perform background task with a fresh context
    func performBackgroundTask<T: Sendable>(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            persistenceController.container.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Error Handling

enum CoreDataError: Error, Sendable {
    case batchDeleteFailed
    case saveError(String)
    
    var localizedDescription: String {
        switch self {
        case .batchDeleteFailed:
            return "Batch delete operation failed"
        case .saveError(let message):
            return "Save failed: \(message)"
        }
    }
}
