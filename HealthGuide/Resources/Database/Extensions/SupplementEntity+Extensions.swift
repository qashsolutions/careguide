//
//  SupplementEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for SupplementEntity with CloudKit default values
//  Production-ready implementation for supplement tracking
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension SupplementEntity {
    
    // MARK: - Supplement Categories
    public enum SupplementCategory: String, CaseIterable, Sendable {
        case vitamin = "Vitamin"
        case mineral = "Mineral"
        case herbal = "Herbal"
        case probiotic = "Probiotic"
        case omega = "Omega/Fish Oil"
        case protein = "Protein"
        case fiber = "Fiber"
        case other = "Other"
        
        /// Default category
        static let defaultCategory = SupplementCategory.vitamin
        
        /// Icon for UI display
        var iconName: String {
            switch self {
            case .vitamin: return "pills"
            case .mineral: return "drop.fill"
            case .herbal: return "leaf.fill"
            case .probiotic: return "shield.lefthalf.filled"
            case .omega: return "drop.circle.fill"
            case .protein: return "bolt.fill"
            case .fiber: return "leaf.arrow.circlepath"
            case .other: return "capsule.fill"
            }
        }
        
        /// Color for UI display
        var colorName: String {
            switch self {
            case .vitamin: return "orange"
            case .mineral: return "blue"
            case .herbal: return "green"
            case .probiotic: return "purple"
            case .omega: return "cyan"
            case .protein: return "red"
            case .fiber: return "brown"
            case .other: return "gray"
            }
        }
        
        /// SwiftUI Color
        var color: Color {
            return Color(colorName)
        }
    }
    
    // MARK: - Common Units
    public enum SupplementUnit: String, CaseIterable, Sendable {
        case mg = "mg"
        case mcg = "mcg"
        case g = "g"
        case ml = "ml"
        case iu = "IU"
        case capsule = "capsule"
        case tablet = "tablet"
        case drop = "drop"
        case scoop = "scoop"
        
        /// Default unit
        static let defaultUnit = SupplementUnit.mg
        
        /// Plural form for display
        func pluralForm(count: Int) -> String {
            switch self {
            case .mg, .mcg, .g, .ml, .iu:
                return self.rawValue // These don't change
            case .capsule:
                return count == 1 ? "capsule" : "capsules"
            case .tablet:
                return count == 1 ? "tablet" : "tablets"
            case .drop:
                return count == 1 ? "drop" : "drops"
            case .scoop:
                return count == 1 ? "scoop" : "scoops"
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
            print("💊 SupplementEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set timestamps
        if createdAt == nil {
            createdAt = Date()
        }
        
        if updatedAt == nil {
            updatedAt = Date()
        }
        
        // Set default active status
        // isActive is non-optional Bool, always set default
        isActive = true
        #if DEBUG
        print("✓ SupplementEntity: Set active status")
        #endif
        
        // Set default quantity
        // quantity is non-optional Int32, always set default
        quantity = 1
        #if DEBUG
        print("📦 SupplementEntity: Set default quantity: 1")
        #endif
        
        // Validate existing data
        validateAndFixData()
        
        #if DEBUG
        print("✅ SupplementEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes data integrity
    private func validateAndFixData() {
        // Validate category if set
        if let currentCategory = category, !currentCategory.isEmpty {
            let validCategories = SupplementCategory.allCases.map { $0.rawValue }
            if !validCategories.contains(currentCategory) {
                let oldValue = currentCategory
                category = SupplementCategory.defaultCategory.rawValue
                
                #if DEBUG
                print("⚠️ SupplementEntity: Invalid category '\(oldValue)' fixed to '\(category!)'")
                #endif
                
                postValidationError(field: "category", oldValue: oldValue, newValue: category!)
            }
        }
        
        // Validate unit if set
        if let currentUnit = unit, !currentUnit.isEmpty {
            let validUnits = SupplementUnit.allCases.map { $0.rawValue }
            if !validUnits.contains(currentUnit) {
                let oldValue = currentUnit
                unit = SupplementUnit.defaultUnit.rawValue
                
                #if DEBUG
                print("⚠️ SupplementEntity: Invalid unit '\(oldValue)' fixed to '\(unit!)'")
                #endif
                
                postValidationError(field: "unit", oldValue: oldValue, newValue: unit!)
            }
        }
        
        // Ensure quantity is positive
        if quantity < 1 {
            let oldValue = quantity
            quantity = 1
            #if DEBUG
            print("⚠️ SupplementEntity: Invalid quantity \(oldValue) fixed to 1")
            #endif
            
            postValidationError(field: "quantity", oldValue: "\(oldValue)", newValue: "1")
        }
    }
    
    /// Post validation error notification
    private func postValidationError(field: String, oldValue: String, newValue: String) {
        NotificationCenter.default.post(
            name: .coreDataEntityError,
            object: nil,
            userInfo: [
                "entity": "SupplementEntity",
                "field": field,
                "error": "Invalid \(field) value: \(oldValue)",
                "fallbackValue": newValue,
                "action": "validation_fix"
            ]
        )
    }
    
    // MARK: - Helper Methods
    
    /// Set category with validation
    public func setCategory(_ newCategory: SupplementCategory) {
        category = newCategory.rawValue
        updatedAt = Date()
        #if DEBUG
        print("🏷️ SupplementEntity: Updated category to \(newCategory.rawValue)")
        #endif
    }
    
    /// Get category as enum
    public var supplementCategory: SupplementCategory? {
        guard let category = category else { return nil }
        return SupplementCategory(rawValue: category)
    }
    
    /// Get category color for SwiftUI
    public var categoryColor: Color {
        return supplementCategory?.color ?? Color.gray
    }
    
    /// Get category icon name
    public var categoryIconName: String {
        return supplementCategory?.iconName ?? "capsule.fill"
    }
    
    /// Set unit with validation
    public func setUnit(_ newUnit: SupplementUnit) {
        unit = newUnit.rawValue
        updatedAt = Date()
        #if DEBUG
        print("📏 SupplementEntity: Updated unit to \(newUnit.rawValue)")
        #endif
    }
    
    /// Get unit as enum
    public var supplementUnit: SupplementUnit? {
        guard let unit = unit else { return nil }
        return SupplementUnit(rawValue: unit)
    }
    
    /// Get formatted dosage string
    public var formattedDosage: String {
        guard let dosage = dosage, !dosage.isEmpty else { return "No dosage" }
        
        if let unit = supplementUnit {
            let unitDisplay = unit.pluralForm(count: Int(quantity))
            return "\(dosage) \(unitDisplay)"
        }
        
        return dosage
    }
    
    /// Get display name with brand
    public var displayName: String {
        var display = name ?? "Unnamed Supplement"
        if let brand = brand, !brand.isEmpty {
            display += " (\(brand))"
        }
        return display
    }
    
    /// Check if supplement has complete information
    public var isComplete: Bool {
        guard let name = name, !name.isEmpty,
              let dosage = dosage, !dosage.isEmpty,
              unit != nil else {
            return false
        }
        return true
    }
    
    /// Toggle active status
    public func toggleActive() {
        isActive = !isActive
        updatedAt = Date()
        #if DEBUG
        print("🔄 SupplementEntity: Toggled active status to \(isActive)")
        #endif
    }
    
    /// Check for potential interactions
    public func hasInteractionWarning() -> Bool {
        guard let interactions = interactions, !interactions.isEmpty else { return false }
        // Check for common warning keywords
        let warningKeywords = ["warning", "caution", "avoid", "interaction", "contraindicated"]
        let lowercasedInteractions = interactions.lowercased()
        return warningKeywords.contains { lowercasedInteractions.contains($0) }
    }
    
    /// Get interaction severity
    public var interactionSeverity: String {
        guard hasInteractionWarning() else { return "none" }
        
        let interactions = (self.interactions ?? "").lowercased()
        if interactions.contains("contraindicated") || interactions.contains("severe") {
            return "high"
        } else if interactions.contains("caution") || interactions.contains("moderate") {
            return "medium"
        } else {
            return "low"
        }
    }
    
    /// Search helper - check if supplement matches search term
    public func matches(searchTerm: String) -> Bool {
        let lowercasedSearch = searchTerm.lowercased()
        
        // Check name
        if let name = name?.lowercased(), name.contains(lowercasedSearch) {
            return true
        }
        
        // Check brand
        if let brand = brand?.lowercased(), brand.contains(lowercasedSearch) {
            return true
        }
        
        // Check category
        if let category = category?.lowercased(), category.contains(lowercasedSearch) {
            return true
        }
        
        // Check purpose
        if let purpose = purpose?.lowercased(), purpose.contains(lowercasedSearch) {
            return true
        }
        
        // Check notes
        if let notes = notes?.lowercased(), notes.contains(lowercasedSearch) {
            return true
        }
        
        return false
    }
    
    /// Update quantity safely
    public func updateQuantity(_ newQuantity: Int32) {
        guard newQuantity >= 0 else {
            #if DEBUG
            print("⚠️ SupplementEntity: Attempted to set negative quantity")
            #endif
            return
        }
        
        quantity = newQuantity
        updatedAt = Date()
        
        #if DEBUG
        print("📦 SupplementEntity: Updated quantity to \(newQuantity)")
        #endif
    }
}
