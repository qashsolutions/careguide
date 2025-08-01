//
//  MedicationEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for MedicationEntity with CloudKit default values
//  Production-ready implementation for medication management
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension MedicationEntity {
    
    // MARK: - Medication Categories
    public enum MedicationCategory: String, CaseIterable, Sendable {
        case heartBloodPressure = "Heart & Blood Pressure"
        case diabetes = "Diabetes"
        case painRelief = "Pain Relief"
        case antibiotic = "Antibiotic"
        case vitamin = "Vitamin"
        case digestive = "Digestive"
        case respiratory = "Respiratory"
        case mental = "Mental Health"
        case thyroid = "Thyroid"
        case other = "Other"
        
        /// Default category
        static let defaultCategory = MedicationCategory.other
        
        /// Icon for UI display
        var iconName: String {
            switch self {
            case .heartBloodPressure: return "heart.fill"
            case .diabetes: return "drop.fill"
            case .painRelief: return "bandage.fill"
            case .antibiotic: return "pills.fill"
            case .vitamin: return "leaf.fill"
            case .digestive: return "stomach"
            case .respiratory: return "lungs.fill"
            case .mental: return "brain"
            case .thyroid: return "butterfly"
            case .other: return "pills"
            }
        }
        
        /// Color for UI display
        var colorName: String {
            switch self {
            case .heartBloodPressure: return "red"
            case .diabetes: return "purple"
            case .painRelief: return "orange"
            case .antibiotic: return "green"
            case .vitamin: return "yellow"
            case .digestive: return "brown"
            case .respiratory: return "blue"
            case .mental: return "indigo"
            case .thyroid: return "teal"
            case .other: return "gray"
            }
        }
        
        /// SwiftUI Color
        var color: Color {
            return Color(colorName)
        }
        
        /// Priority for sorting (critical meds first)
        var priority: Int {
            switch self {
            case .heartBloodPressure: return 1
            case .diabetes: return 2
            case .antibiotic: return 3
            case .thyroid: return 4
            case .mental: return 5
            case .respiratory: return 6
            case .painRelief: return 7
            case .digestive: return 8
            case .vitamin: return 9
            case .other: return 10
            }
        }
    }
    
    // MARK: - Medication Units
    public enum MedicationUnit: String, CaseIterable, Sendable {
        case mg = "mg"
        case mcg = "mcg"
        case g = "g"
        case ml = "ml"
        case unit = "unit"
        case tablet = "tablet"
        case capsule = "capsule"
        case patch = "patch"
        case drop = "drop"
        case puff = "puff"
        case injection = "injection"
        
        /// Default unit
        static let defaultUnit = MedicationUnit.mg
        
        /// Plural form for display
        func pluralForm(count: Int) -> String {
            switch self {
            case .mg, .mcg, .g, .ml:
                return self.rawValue
            case .unit:
                return count == 1 ? "unit" : "units"
            case .tablet:
                return count == 1 ? "tablet" : "tablets"
            case .capsule:
                return count == 1 ? "capsule" : "capsules"
            case .patch:
                return count == 1 ? "patch" : "patches"
            case .drop:
                return count == 1 ? "drop" : "drops"
            case .puff:
                return count == 1 ? "puff" : "puffs"
            case .injection:
                return count == 1 ? "injection" : "injections"
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
            print("💊 MedicationEntity: Generated ID: \(id!)")
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
        print("✓ MedicationEntity: Set active status")
        #endif
        
        // Set default quantity
        // quantity is non-optional Int32, always set default
        quantity = 1
        #if DEBUG
        print("📦 MedicationEntity: Set default quantity: 1")
        #endif
        
        // Set required name if nil
        if name == nil {
            name = ""
            #if DEBUG
            print("📝 MedicationEntity: Set empty name")
            #endif
        }
        
        // Validate existing data
        validateAndFixData()
        
        #if DEBUG
        print("✅ MedicationEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes data integrity
    private func validateAndFixData() {
        // Validate category if set
        if let currentCategory = category, !currentCategory.isEmpty {
            let validCategories = MedicationCategory.allCases.map { $0.rawValue }
            if !validCategories.contains(currentCategory) {
                let oldValue = currentCategory
                category = MedicationCategory.defaultCategory.rawValue
                
                #if DEBUG
                print("⚠️ MedicationEntity: Invalid category '\(oldValue)' fixed to '\(category!)'")
                #endif
                
                postValidationError(field: "category", oldValue: oldValue, newValue: category!)
            }
        }
        
        // Validate unit if set
        if let currentUnit = unit, !currentUnit.isEmpty {
            let validUnits = MedicationUnit.allCases.map { $0.rawValue }
            if !validUnits.contains(currentUnit) {
                let oldValue = currentUnit
                unit = MedicationUnit.defaultUnit.rawValue
                
                #if DEBUG
                print("⚠️ MedicationEntity: Invalid unit '\(oldValue)' fixed to '\(unit!)'")
                #endif
                
                postValidationError(field: "unit", oldValue: oldValue, newValue: unit!)
            }
        }
        
        // Ensure quantity is positive
        if quantity < 1 {
            let oldValue = quantity
            quantity = 1
            #if DEBUG
            print("⚠️ MedicationEntity: Invalid quantity \(oldValue) fixed to 1")
            #endif
            
            postValidationError(field: "quantity", oldValue: "\(oldValue)", newValue: "1")
        }
        
        // Validate refills remaining
        if refillsRemaining < 0 {
            refillsRemaining = 0
            #if DEBUG
            print("⚠️ MedicationEntity: Negative refills fixed to 0")
            #endif
        }
    }
    
    /// Post validation error notification
    private func postValidationError(field: String, oldValue: String, newValue: String) {
        NotificationCenter.default.post(
            name: .coreDataEntityError,
            object: nil,
            userInfo: [
                "entity": "MedicationEntity",
                "field": field,
                "error": "Invalid \(field) value: \(oldValue)",
                "fallbackValue": newValue,
                "action": "validation_fix"
            ]
        )
    }
    
    // MARK: - Helper Methods
    
    /// Set category with validation
    public func setCategory(_ newCategory: MedicationCategory) {
        category = newCategory.rawValue
        updatedAt = Date()
        #if DEBUG
        print("🏷️ MedicationEntity: Updated category to \(newCategory.rawValue)")
        #endif
    }
    
    /// Get category as enum
    public var medicationCategory: MedicationCategory? {
        guard let category = category else { return nil }
        return MedicationCategory(rawValue: category)
    }
    
    /// Get category color for SwiftUI
    public var categoryColor: Color {
        return medicationCategory?.color ?? Color.gray
    }
    
    /// Get category icon name
    public var categoryIconName: String {
        return medicationCategory?.iconName ?? "pills"
    }
    
    /// Set unit with validation
    public func setUnit(_ newUnit: MedicationUnit) {
        unit = newUnit.rawValue
        updatedAt = Date()
        #if DEBUG
        print("📏 MedicationEntity: Updated unit to \(newUnit.rawValue)")
        #endif
    }
    
    /// Get unit as enum
    public var medicationUnit: MedicationUnit? {
        guard let unit = unit else { return nil }
        return MedicationUnit(rawValue: unit)
    }
    
    /// Get formatted dosage string
    public var formattedDosage: String {
        guard let dosage = dosage, !dosage.isEmpty else { return "No dosage" }
        
        if let unit = medicationUnit {
            let unitDisplay = unit.pluralForm(count: Int(quantity))
            return "\(dosage) \(unitDisplay)"
        }
        
        return dosage
    }
    
    /// Get display name
    public var displayName: String {
        return name ?? "Unnamed Medication"
    }
    
    /// Toggle active status
    public func toggleActive() {
        isActive = !isActive
        updatedAt = Date()
        #if DEBUG
        print("🔄 MedicationEntity: Toggled active status to \(isActive)")
        #endif
    }
    
    /// Check if medication is expired
    public var isExpired: Bool {
        guard let expDate = expirationDate else { return false }
        return expDate < Date()
    }
    
    /// Days until expiration
    public var daysUntilExpiration: Int? {
        guard let expDate = expirationDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expDate).day
        return days
    }
    
    /// Get expiration status
    public var expirationStatus: (text: String, color: Color) {
        guard let days = daysUntilExpiration else {
            return ("No expiration date", .gray)
        }
        
        if days < 0 {
            return ("Expired \(abs(days)) days ago", .red)
        } else if days == 0 {
            return ("Expires today", .red)
        } else if days <= 30 {
            return ("Expires in \(days) days", .orange)
        } else if days <= 90 {
            return ("Expires in \(days) days", .yellow)
        } else {
            return ("Expires in \(days) days", .green)
        }
    }
    
    /// Check if refill needed
    public var needsRefill: Bool {
        return refillsRemaining <= 1
    }
    
    /// Get refill status
    public var refillStatus: (text: String, color: Color) {
        let refills = refillsRemaining
        
        if refills == 0 {
            return ("No refills remaining", .red)
        } else if refills == 1 {
            return ("1 refill remaining", .orange)
        } else {
            return ("\(refills) refills remaining", .green)
        }
    }
    
    /// Update quantity safely
    public func updateQuantity(_ newQuantity: Int32) {
        guard newQuantity >= 0 else {
            #if DEBUG
            print("⚠️ MedicationEntity: Attempted to set negative quantity")
            #endif
            return
        }
        
        quantity = newQuantity
        updatedAt = Date()
        
        #if DEBUG
        print("📦 MedicationEntity: Updated quantity to \(newQuantity)")
        #endif
    }
    
    /// Update refills safely
    public func updateRefills(_ newRefills: Int32) {
        guard newRefills >= 0 else {
            #if DEBUG
            print("⚠️ MedicationEntity: Attempted to set negative refills")
            #endif
            return
        }
        
        refillsRemaining = newRefills
        updatedAt = Date()
        
        #if DEBUG
        print("🔄 MedicationEntity: Updated refills to \(newRefills)")
        #endif
    }
    
    /// Search helper - check if medication matches search term
    public func matches(searchTerm: String) -> Bool {
        let lowercasedSearch = searchTerm.lowercased()
        
        // Check name
        if let name = name?.lowercased(), name.contains(lowercasedSearch) {
            return true
        }
        
        // Check category
        if let category = category?.lowercased(), category.contains(lowercasedSearch) {
            return true
        }
        
        // Check prescriber
        if let prescriber = prescribedBy?.lowercased(), prescriber.contains(lowercasedSearch) {
            return true
        }
        
        // Check prescription number
        if let rxNumber = prescriptionNumber?.lowercased(), rxNumber.contains(lowercasedSearch) {
            return true
        }
        
        // Check notes
        if let notes = notes?.lowercased(), notes.contains(lowercasedSearch) {
            return true
        }
        
        return false
    }
    
    /// Get sort priority (critical meds first)
    public var sortPriority: Int {
        var priority = medicationCategory?.priority ?? 999
        
        // Expired meds get highest priority
        if isExpired {
            priority -= 1000
        }
        // Meds needing refill get higher priority
        else if needsRefill {
            priority -= 100
        }
        
        return priority
    }
}
