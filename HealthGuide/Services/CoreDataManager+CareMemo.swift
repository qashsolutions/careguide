//
//  CoreDataManager+CareMemo.swift
//  HealthGuide
//
//  Core Data operations for CareMemos with 10 memo limit
//  Production-ready with automatic cleanup
//

import Foundation
@preconcurrency import CoreData

@available(iOS 18.0, *)
extension CoreDataManager {
    
    // MARK: - Constants
    private static let maxMemoCount = 10
    
    // MARK: - Save CareMemo
    func saveCareMemo(_ memo: CareMemo) async throws {
        print("🧵 [CoreData] saveCareMemo called - async context")
        print("🧵 [CoreData] Context type: \(context.concurrencyType.rawValue) (0=confinement, 1=private, 2=main)")
        print("🧵 [CoreData] Context description: \(context)")
        
        try await context.perform { @Sendable [context] in
            print("🧵 [CoreData] Inside context.perform - Thread: \(Thread.current)")
            print("🧵 [CoreData] Inside context.perform - Is Main: \(Thread.isMainThread)")
            
            // Check existing memo count
            let fetchRequest = CareMemoEntity.fetchRequest()
            let existingMemos = try context.fetch(fetchRequest)
            
            // If at limit, delete oldest
            if existingMemos.count >= Self.maxMemoCount {
                let sortedMemos = existingMemos.sorted { 
                    ($0.recordedAt ?? Date.distantPast) < ($1.recordedAt ?? Date.distantPast)
                }
                
                if let oldestMemo = sortedMemos.first {
                    // Delete audio file
                    if let urlString = oldestMemo.audioFileURL,
                       let url = URL(string: urlString) {
                        try? FileManager.default.removeItem(at: url)
                    }
                    
                    // Delete Core Data entity
                    context.delete(oldestMemo)
                }
            }
            
            // Create new memo entity
            let entity = CareMemoEntity(context: context)
            entity.id = memo.id
            entity.audioFileURL = memo.audioFileURL
            entity.duration = memo.duration
            entity.recordedAt = memo.recordedAt
            entity.title = memo.title
            entity.transcription = memo.transcription
            entity.priority = memo.priority.rawValue
            
            // Save related medication IDs as data
            if !memo.relatedMedicationIds.isEmpty {
                entity.relatedMedicationIds = try JSONEncoder().encode(memo.relatedMedicationIds)
            }
            
            try context.save()
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .careMemoDataDidChange, object: nil)
        }
    }
    
    // MARK: - Fetch CareMemos
    func fetchCareMemos() async throws -> [CareMemo] {
        try await context.perform { @Sendable [context] in
            let request = CareMemoEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "recordedAt", ascending: false)
            ]
            
            let entities = try context.fetch(request)
            return entities.compactMap { entity in
                guard let id = entity.id,
                      let audioFileURL = entity.audioFileURL else { return nil }
                
                // Decode medication IDs
                var medicationIds: [UUID] = []
                if let data = entity.relatedMedicationIds {
                    medicationIds = (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
                }
                
                return CareMemo(
                    id: id,
                    audioFileURL: audioFileURL,
                    duration: entity.duration,
                    recordedAt: entity.recordedAt ?? Date(),
                    title: entity.title,
                    transcription: entity.transcription,
                    relatedMedicationIds: medicationIds,
                    priority: MemoPriority(rawValue: entity.priority ?? "Medium") ?? .medium
                )
            }
        }
    }
    
    // MARK: - Delete CareMemo
    func deleteCareMemo(_ id: UUID) async throws {
        try await context.perform { @Sendable [context] in
            let request = CareMemoEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            if let entity = try context.fetch(request).first {
                // Delete audio file
                if let urlString = entity.audioFileURL,
                   let url = URL(string: urlString) {
                    try? FileManager.default.removeItem(at: url)
                }
                
                // Delete entity
                context.delete(entity)
                try context.save()
            }
        }
        
        await MainActor.run {
            NotificationCenter.default.post(name: .careMemoDataDidChange, object: nil)
        }
    }
    
    // MARK: - Get Memo Count
    func getCareMemoCount() async throws -> Int {
        try await context.perform { @Sendable [context] in
            let request = NSFetchRequest<NSNumber>(entityName: "CareMemoEntity")
            request.resultType = .countResultType
            
            let results = try context.execute(request) as? NSAsynchronousFetchResult<NSNumber>
            return results?.finalResult?.first?.intValue ?? 0
        }
    }
    
    // MARK: - Cleanup Orphaned Files
    func cleanupOrphanedMemoFiles() async {
        await Task.detached(priority: .background) {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let memosFolderURL = documentsPath.appendingPathComponent("CareMemos", isDirectory: true)
            
            guard let files = try? FileManager.default.contentsOfDirectory(at: memosFolderURL, 
                                                                          includingPropertiesForKeys: nil) else { return }
            
            // Get all valid URLs from Core Data
            let validURLs = await self.getValidMemoURLs()
            
            // Delete orphaned files
            for file in files {
                if !validURLs.contains(file.absoluteString) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }.value
    }
    
    private func getValidMemoURLs() async -> Set<String> {
        do {
            let memos = try await fetchCareMemos()
            return Set(memos.map { $0.audioFileURL })
        } catch {
            return []
        }
    }
}

// MARK: - Notification Names
@available(iOS 18.0, *)
extension Notification.Name {
    static let careMemoDataDidChange = Notification.Name("careMemoDataDidChange")
}
