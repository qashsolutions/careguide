//
//  DocumentEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for DocumentEntity with CloudKit default values
//  Production-ready implementation for document storage management
//

import Foundation
import CoreData
import SwiftUI
import UniformTypeIdentifiers

@available(iOS 18.0, *)
extension DocumentEntity {
    
    // MARK: - File Type Enum
    public enum FileType: String, CaseIterable {
        case pdf = "pdf"
        case jpg = "jpg"
        case jpeg = "jpeg"
        case png = "png"
        case heic = "heic"
        
        var displayName: String {
            switch self {
            case .pdf: return "PDF"
            case .jpg, .jpeg: return "JPEG"
            case .png: return "PNG"
            case .heic: return "HEIC"
            }
        }
        
        var iconName: String {
            switch self {
            case .pdf: return "doc.text.fill"
            case .jpg, .jpeg, .png, .heic: return "photo.fill"
            }
        }
        
        var utType: UTType {
            switch self {
            case .pdf: return .pdf
            case .jpg, .jpeg: return .jpeg
            case .png: return .png
            case .heic: return .heic
            }
        }
        
        static func from(filename: String) -> FileType? {
            let ext = (filename as NSString).pathExtension.lowercased()
            return FileType(rawValue: ext)
        }
    }
    
    // MARK: - Constants
    public static let maxFileSize: Int64 = 3 * 1024 * 1024 // 3 MB
    public static let maxTotalStorage: Int64 = 15 * 1024 * 1024 // 15 MB
    
    // MARK: - awakeFromInsert
    /// Called when entity is first inserted into context
    /// Sets default values for required fields to ensure CloudKit compatibility
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Generate unique ID
        if id == nil {
            id = UUID()
            #if DEBUG
            print("📎 DocumentEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set required string fields to empty if nil
        if filename == nil {
            filename = ""
            #if DEBUG
            print("📝 DocumentEntity: Set empty filename")
            #endif
        }
        
        if category == nil {
            category = ""
            #if DEBUG
            print("📁 DocumentEntity: Set empty category")
            #endif
        }
        
        if localPath == nil {
            localPath = ""
            #if DEBUG
            print("📂 DocumentEntity: Set empty localPath")
            #endif
        }
        
        // Set creation date
        if createdAt == nil {
            createdAt = Date()
            #if DEBUG
            print("📅 DocumentEntity: Set creation date")
            #endif
        }
        
        // Initialize file size to 0
        fileSize = 0
        #if DEBUG
        print("📦 DocumentEntity: Set file size to 0")
        #endif
        
        #if DEBUG
        print("✅ DocumentEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - File Management
    
    /// Get the documents directory URL
    public static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    /// Get the medical documents subdirectory
    public static var medicalDocumentsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("MedicalDocuments", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        
        return url
    }
    
    /// Get full file URL
    public var fileURL: URL? {
        guard let localPath = localPath, !localPath.isEmpty else { return nil }
        return DocumentEntity.medicalDocumentsDirectory.appendingPathComponent(localPath)
    }
    
    /// Check if file exists
    public var fileExists: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Delete physical file
    public func deleteFile() {
        guard let url = fileURL, fileExists else { return }
        
        do {
            try FileManager.default.removeItem(at: url)
            #if DEBUG
            print("🗑️ DocumentEntity: Deleted file at \(url.lastPathComponent)")
            #endif
        } catch {
            #if DEBUG
            print("❌ DocumentEntity: Failed to delete file: \(error)")
            #endif
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get display name with fallback
    public var displayName: String {
        if let filename = filename, !filename.isEmpty {
            return filename
        }
        return "Unnamed Document"
    }
    
    /// Get file type enum
    public var fileTypeEnum: FileType? {
        guard let fileType = fileType else { return nil }
        return FileType(rawValue: fileType.lowercased())
    }
    
    /// Get formatted file size
    public var formattedFileSize: String {
        return DocumentEntity.formatFileSize(fileSize)
    }
    
    /// Format file size for display
    public static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Get formatted creation date
    public var formattedCreatedDate: String {
        guard let date = createdAt else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Check if file size is within limit
    public static func isFileSizeValid(_ size: Int64) -> Bool {
        return size <= maxFileSize
    }
    
    /// Get total storage used across all documents
    public static func totalStorageUsed(in context: NSManagedObjectContext) -> Int64 {
        let request = DocumentEntity.fetchRequest()
        
        do {
            let documents = try context.fetch(request)
            return documents.reduce(0) { $0 + $1.fileSize }
        } catch {
            #if DEBUG
            print("❌ Error calculating total storage: \(error)")
            #endif
            return 0
        }
    }
    
    /// Check if adding new file would exceed storage limit
    public static func canAddFile(size: Int64, in context: NSManagedObjectContext) -> Bool {
        let currentUsage = totalStorageUsed(in: context)
        return (currentUsage + size) <= maxTotalStorage
    }
    
    /// Get storage usage percentage
    public static func storageUsagePercentage(in context: NSManagedObjectContext) -> Double {
        let used = Double(totalStorageUsed(in: context))
        let total = Double(maxTotalStorage)
        return (used / total) * 100
    }
    
    /// Search helper - check if document matches search term
    public func matches(searchTerm: String) -> Bool {
        let lowercasedSearch = searchTerm.lowercased()
        
        // Check filename
        if let filename = filename?.lowercased(), filename.contains(lowercasedSearch) {
            return true
        }
        
        // Check category
        if let category = category?.lowercased(), category.contains(lowercasedSearch) {
            return true
        }
        
        // Check notes
        if let notes = notes?.lowercased(), notes.contains(lowercasedSearch) {
            return true
        }
        
        return false
    }
    
    /// Generate unique filename if needed
    public static func generateUniqueFilename(originalName: String, in context: NSManagedObjectContext) -> String {
        let request = DocumentEntity.fetchRequest()
        request.predicate = NSPredicate(format: "filename BEGINSWITH %@", originalName)
        
        do {
            let existingDocuments = try context.fetch(request)
            let existingNames = Set(existingDocuments.compactMap { $0.filename })
            
            if !existingNames.contains(originalName) {
                return originalName
            }
            
            // Add number suffix
            var counter = 1
            let nameWithoutExt = (originalName as NSString).deletingPathExtension
            let ext = (originalName as NSString).pathExtension
            
            while true {
                let newName = "\(nameWithoutExt) (\(counter)).\(ext)"
                if !existingNames.contains(newName) {
                    return newName
                }
                counter += 1
            }
        } catch {
            return originalName
        }
    }
    
    /// Create thumbnail if image
    public func createThumbnail() -> UIImage? {
        guard let fileType = fileTypeEnum,
              [.jpg, .jpeg, .png, .heic].contains(fileType),
              let url = fileURL,
              fileExists else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            if let image = UIImage(data: data) {
                // Create thumbnail
                let maxSize: CGFloat = 200
                let scale = min(maxSize / image.size.width, maxSize / image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                
                UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                return thumbnail
            }
        } catch {
            #if DEBUG
            print("❌ Error creating thumbnail: \(error)")
            #endif
        }
        
        return nil
    }
}