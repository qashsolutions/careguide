//
//  DietEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for DietEntity with CloudKit default values
//  Production-ready implementation for diet and meal tracking
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension DietEntity {
    
    // MARK: - Meal Types
    public enum MealType: String, CaseIterable, Sendable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"
        case supplement = "Supplement"
        
        /// Default meal type
        static let defaultMealType = MealType.lunch
        
        /// Icon for UI display
        var iconName: String {
            switch self {
            case .breakfast: return "sun.max.fill"
            case .lunch: return "sun.and.horizon.fill"
            case .dinner: return "moon.stars.fill"
            case .snack: return "carrot.fill"
            case .supplement: return "pills.fill"
            }
        }
        
        /// Typical time ranges
        var typicalTimeRange: String {
            switch self {
            case .breakfast: return "6:00 AM - 10:00 AM"
            case .lunch: return "11:00 AM - 2:00 PM"
            case .dinner: return "5:00 PM - 8:00 PM"
            case .snack: return "Any time"
            case .supplement: return "With meals"
            }
        }
        
        /// Sort order
        var sortOrder: Int {
            switch self {
            case .breakfast: return 0
            case .lunch: return 1
            case .dinner: return 2
            case .snack: return 3
            case .supplement: return 4
            }
        }
    }
    
    // MARK: - Diet Categories
    public enum DietCategory: String, CaseIterable, Sendable {
        case regular = "Regular"
        case diabetic = "Diabetic"
        case lowSodium = "Low Sodium"
        case lowFat = "Low Fat"
        case glutenFree = "Gluten Free"
        case vegetarian = "Vegetarian"
        case pureed = "Pureed"
        case liquid = "Liquid"
        case other = "Other"
        
        /// Default category
        static let defaultCategory = DietCategory.regular
        
        /// Color for UI display
        var colorName: String {
            switch self {
            case .regular: return "green"
            case .diabetic: return "blue"
            case .lowSodium: return "orange"
            case .lowFat: return "yellow"
            case .glutenFree: return "purple"
            case .vegetarian: return "mint"
            case .pureed: return "pink"
            case .liquid: return "cyan"
            case .other: return "gray"
            }
        }
        
        /// SwiftUI Color
        var color: Color {
            return Color(colorName)
        }
    }
    
    // MARK: - Common Restrictions
    public enum DietaryRestriction: String, CaseIterable {
        case noSalt = "No Salt"
        case noSugar = "No Sugar"
        case noGluten = "No Gluten"
        case noDairy = "No Dairy"
        case noNuts = "No Nuts"
        case noShellfish = "No Shellfish"
        case noEggs = "No Eggs"
        case noSoy = "No Soy"
        case noSpicy = "No Spicy"
        case softFoodsOnly = "Soft Foods Only"
        case thickenedLiquids = "Thickened Liquids"
        
        /// Icon for restriction
        var iconName: String {
            switch self {
            case .noSalt: return "drop.slash"
            case .noSugar: return "cube.slash"
            case .noGluten: return "wheat.slash"
            case .noDairy: return "milk.slash"
            case .noNuts, .noShellfish, .noEggs, .noSoy: return "allergens"
            case .noSpicy: return "flame.slash"
            case .softFoodsOnly: return "fork.knife"
            case .thickenedLiquids: return "drop.thick"
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
            print("🍽️ DietEntity: Generated ID: \(id!)")
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
        print("✓ DietEntity: Set active status")
        #endif
        
        // Set default portion if needed
        if portion == nil || portion?.isEmpty == true {
            portion = "1 serving"
            #if DEBUG
            print("🥄 DietEntity: Set default portion: 1 serving")
            #endif
        }
        
        // Initialize empty restrictions array if nil
        if restrictions == nil {
            restrictions = NSArray()
            #if DEBUG
            print("📋 DietEntity: Initialized empty restrictions")
            #endif
        }
        
        // Validate existing data
        validateAndFixData()
        
        #if DEBUG
        print("✅ DietEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes data integrity
    private func validateAndFixData() {
        // Validate meal type if set
        if let currentMealType = mealType, !currentMealType.isEmpty {
            let validMealTypes = MealType.allCases.map { $0.rawValue }
            if !validMealTypes.contains(currentMealType) {
                let oldValue = currentMealType
                mealType = MealType.defaultMealType.rawValue
                
                #if DEBUG
                print("⚠️ DietEntity: Invalid meal type '\(oldValue)' fixed to '\(mealType!)'")
                #endif
                
                postValidationError(field: "mealType", oldValue: oldValue, newValue: mealType!)
            }
        }
        
        // Validate category if set
        if let currentCategory = category, !currentCategory.isEmpty {
            let validCategories = DietCategory.allCases.map { $0.rawValue }
            if !validCategories.contains(currentCategory) {
                let oldValue = currentCategory
                category = DietCategory.defaultCategory.rawValue
                
                #if DEBUG
                print("⚠️ DietEntity: Invalid category '\(oldValue)' fixed to '\(category!)'")
                #endif
                
                postValidationError(field: "category", oldValue: oldValue, newValue: category!)
            }
        }
        
        // Ensure calories are non-negative
        if calories < 0 {
            let oldValue = calories
            calories = 0
            #if DEBUG
            print("⚠️ DietEntity: Invalid calories \(oldValue) fixed to 0")
            #endif
            
            postValidationError(field: "calories", oldValue: "\(oldValue)", newValue: "0")
        }
    }
    
    /// Post validation error notification
    private func postValidationError(field: String, oldValue: String, newValue: String) {
        NotificationCenter.default.post(
            name: .coreDataEntityError,
            object: nil,
            userInfo: [
                "entity": "DietEntity",
                "field": field,
                "error": "Invalid \(field) value: \(oldValue)",
                "fallbackValue": newValue,
                "action": "validation_fix"
            ]
        )
    }
    
    // MARK: - Helper Methods
    
    /// Set meal type with validation
    public func setMealType(_ newMealType: MealType) {
        mealType = newMealType.rawValue
        updatedAt = Date()
        #if DEBUG
        print("🍽️ DietEntity: Updated meal type to \(newMealType.rawValue)")
        #endif
    }
    
    /// Get meal type as enum
    public var dietMealType: MealType? {
        guard let mealType = mealType else { return nil }
        return MealType(rawValue: mealType)
    }
    
    /// Set category with validation
    public func setCategory(_ newCategory: DietCategory) {
        category = newCategory.rawValue
        updatedAt = Date()
        #if DEBUG
        print("🏷️ DietEntity: Updated category to \(newCategory.rawValue)")
        #endif
    }
    
    /// Get category as enum
    public var dietCategory: DietCategory? {
        guard let category = category else { return nil }
        return DietCategory(rawValue: category)
    }
    
    /// Get category color for SwiftUI
    public var categoryColor: Color {
        return dietCategory?.color ?? Color.gray
    }
    
    /// Get meal type icon
    public var mealTypeIconName: String {
        return dietMealType?.iconName ?? "fork.knife"
    }
    
    /// Add dietary restriction
    public func addRestriction(_ restriction: DietaryRestriction) {
        var currentRestrictions = restrictionsArray
        if !currentRestrictions.contains(restriction.rawValue) {
            currentRestrictions.append(restriction.rawValue)
            restrictions = currentRestrictions as NSArray
            updatedAt = Date()
            
            #if DEBUG
            print("➕ DietEntity: Added restriction: \(restriction.rawValue)")
            #endif
        }
    }
    
    /// Remove dietary restriction
    public func removeRestriction(_ restriction: DietaryRestriction) {
        var currentRestrictions = restrictionsArray
        currentRestrictions.removeAll { $0 == restriction.rawValue }
        restrictions = currentRestrictions as NSArray
        updatedAt = Date()
        
        #if DEBUG
        print("➖ DietEntity: Removed restriction: \(restriction.rawValue)")
        #endif
    }
    
    /// Get restrictions as string array
    public var restrictionsArray: [String] {
        return (restrictions as? [String]) ?? []
    }
    
    /// Check if has specific restriction
    public func hasRestriction(_ restriction: DietaryRestriction) -> Bool {
        return restrictionsArray.contains(restriction.rawValue)
    }
    
    /// Get formatted restrictions text
    public var formattedRestrictions: String {
        let restrictionsList = restrictionsArray
        if restrictionsList.isEmpty {
            return "No restrictions"
        }
        return restrictionsList.joined(separator: ", ")
    }
    
    /// Get display name with meal type
    public var displayName: String {
        var display = name ?? "Unnamed Item"
        if let mealType = dietMealType {
            display = "\(mealType.rawValue): \(display)"
        }
        return display
    }
    
    /// Get calorie display text
    public var calorieText: String {
        guard calories > 0 else { return "" }
        return "\(calories) cal"
    }
    
    /// Toggle active status
    public func toggleActive() {
        isActive = !isActive
        updatedAt = Date()
        #if DEBUG
        print("🔄 DietEntity: Toggled active status to \(isActive)")
        #endif
    }
    
    /// Check if diet item is suitable for restrictions
    public func isSuitableFor(restrictions: [DietaryRestriction]) -> Bool {
        let itemRestrictions = restrictionsArray
        for restriction in restrictions {
            if itemRestrictions.contains(restriction.rawValue) {
                return false
            }
        }
        return true
    }
    
    /// Update calories safely
    public func updateCalories(_ newCalories: Int32) {
        guard newCalories >= 0 else {
            #if DEBUG
            print("⚠️ DietEntity: Attempted to set negative calories")
            #endif
            return
        }
        
        calories = newCalories
        updatedAt = Date()
        
        #if DEBUG
        print("🔥 DietEntity: Updated calories to \(newCalories)")
        #endif
    }
    
    /// Search helper - check if diet item matches search term
    public func matches(searchTerm: String) -> Bool {
        let lowercasedSearch = searchTerm.lowercased()
        
        // Check name
        if let name = name?.lowercased(), name.contains(lowercasedSearch) {
            return true
        }
        
        // Check meal type
        if let mealType = mealType?.lowercased(), mealType.contains(lowercasedSearch) {
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
        
        // Check restrictions
        if restrictionsArray.contains(where: { $0.lowercased().contains(lowercasedSearch) }) {
            return true
        }
        
        return false
    }
}
