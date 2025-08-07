//
//  DocumentCategoryEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for DocumentCategoryEntity with CloudKit default values
//  Production-ready implementation for document folder management
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension DocumentCategoryEntity {
    
    // MARK: - Default Icon Names
    public enum DefaultIcons {
        static let labResults = "doc.text.fill"
        static let prescriptions = "pills.fill"
        static let insurance = "creditcard.fill"
        static let immunization = "syringe.fill"
        static let imaging = "camera.viewfinder"
        static let general = "folder.fill"
        static let emergency = "staroflife.fill"
        static let dental = "cross.case.fill"
        static let vision = "eye.fill"
        static let other = "doc.fill"
    }
    
    // MARK: - Default Categories
    public enum DefaultCategory: String, CaseIterable {
        case labResults = "Lab Results"
        case prescriptions = "Prescriptions"
        case insurance = "Insurance"
        case immunization = "Immunization"
        case imaging = "Imaging"
        case emergency = "Emergency"
        case dental = "Dental"
        case vision = "Vision"
        case general = "General"
        
        var iconName: String {
            switch self {
            case .labResults: return DefaultIcons.labResults
            case .prescriptions: return DefaultIcons.prescriptions
            case .insurance: return DefaultIcons.insurance
            case .immunization: return DefaultIcons.immunization
            case .imaging: return DefaultIcons.imaging
            case .emergency: return DefaultIcons.emergency
            case .dental: return DefaultIcons.dental
            case .vision: return DefaultIcons.vision
            case .general: return DefaultIcons.general
            }
        }
        
        var color: Color {
            switch self {
            case .labResults: return .blue
            case .prescriptions: return .green
            case .insurance: return .orange
            case .immunization: return .purple
            case .imaging: return .indigo
            case .emergency: return .red
            case .dental: return .cyan
            case .vision: return .mint
            case .general: return .gray
            }
        }
    }
    
    // MARK: - awakeFromInsert
    /// Called when entity is first inserted into context
    /// Sets default values for required fields to ensure CloudKit compatibility
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        // Generate unique ID
        if id == nil {
            id = UUID()
            #if DEBUG
            print("📁 DocumentCategoryEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set required string fields to empty if nil
        if name == nil {
            name = ""
            #if DEBUG
            print("📝 DocumentCategoryEntity: Set empty name")
            #endif
        }
        
        // Set default icon if nil or empty
        if iconName == nil || iconName?.isEmpty == true {
            iconName = DefaultIcons.general
            #if DEBUG
            print("🎨 DocumentCategoryEntity: Set default icon")
            #endif
        }
        
        // Set creation date
        if createdAt == nil {
            createdAt = Date()
            #if DEBUG
            print("📅 DocumentCategoryEntity: Set creation date")
            #endif
        }
        
        // Initialize document count
        documentCount = 0
        #if DEBUG
        print("📊 DocumentCategoryEntity: Initialized document count to 0")
        #endif
        
        #if DEBUG
        print("✅ DocumentCategoryEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Helper Methods
    
    /// Update document count
    public func updateDocumentCount() {
        if let documents = documents as? Set<DocumentEntity> {
            let activeDocuments = documents.filter { $0.localPath != nil && !$0.localPath!.isEmpty }
            self.documentCount = Int32(activeDocuments.count)
            
            #if DEBUG
            print("📊 DocumentCategoryEntity: Updated document count to \(documentCount)")
            #endif
        }
    }
    
    /// Get total size of all documents in category
    public var totalSize: Int64 {
        guard let documents = documents as? Set<DocumentEntity> else { return 0 }
        return documents.reduce(0) { $0 + $1.fileSize }
    }
    
    /// Get formatted total size
    public var formattedTotalSize: String {
        return DocumentEntity.formatFileSize(totalSize)
    }
    
    /// Check if category can be deleted (not a default category with documents)
    public var canBeDeleted: Bool {
        // Allow deletion of custom categories or empty default categories
        if let documents = documents as? Set<DocumentEntity>, !documents.isEmpty {
            return false
        }
        return true
    }
    
    /// Get display name with fallback
    public var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        return "Unnamed Folder"
    }
    
    /// Get color for category
    public var categoryColor: Color {
        // Try to match with default category
        if let name = name,
           let defaultCategory = DefaultCategory.allCases.first(where: { $0.rawValue == name }) {
            return defaultCategory.color
        }
        // Default color for custom categories
        return .blue
    }
    
    /// Create default categories if needed
    public static func createDefaultCategoriesIfNeeded(in context: NSManagedObjectContext) {
        let request = DocumentCategoryEntity.fetchRequest()
        
        do {
            let existingCategories = try context.fetch(request)
            let existingNames = Set(existingCategories.compactMap { $0.name })
            
            // Fix any categories with empty icon names
            for category in existingCategories {
                if category.iconName == nil || category.iconName?.isEmpty == true {
                    // Try to match with default category
                    if let defaultCategory = DefaultCategory.allCases.first(where: { $0.rawValue == category.name }) {
                        category.iconName = defaultCategory.iconName
                    } else {
                        category.iconName = DefaultIcons.general
                    }
                    #if DEBUG
                    print("🔧 Fixed empty icon for category: \(category.name ?? "unknown")")
                    #endif
                }
            }
            
            for defaultCategory in DefaultCategory.allCases {
                if !existingNames.contains(defaultCategory.rawValue) {
                    let category = DocumentCategoryEntity(context: context)
                    category.name = defaultCategory.rawValue
                    category.iconName = defaultCategory.iconName
                    
                    #if DEBUG
                    print("📁 Created default category: \(defaultCategory.rawValue)")
                    #endif
                }
            }
            
            if context.hasChanges {
                try context.save()
            }
        } catch {
            #if DEBUG
            print("❌ Error creating default categories: \(error)")
            #endif
        }
    }
}