//
//  Diet.swift
//  HealthGuide
//
//  Diet model for meal tracking
//  Flexible scheduling for 2-4 meals per day
//

import Foundation
import SwiftUI

@available(iOS 18.0, *)
struct Diet: HealthItem, Sendable {
    let id: UUID
    var name: String
    var portion: String
    var notes: String?
    var schedule: Schedule
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Diet-specific properties
    var category: DietCategory?
    var calories: Int?
    var restrictions: Set<DietaryRestriction>
    var mealType: MealType?
    
    init(
        id: UUID = UUID(),
        name: String,
        portion: String = "1 serving",
        notes: String? = nil,
        schedule: Schedule = Schedule(),
        isActive: Bool = true,
        category: DietCategory? = nil,
        calories: Int? = nil,
        restrictions: Set<DietaryRestriction> = [],
        mealType: MealType? = nil
    ) {
        self.id = id
        self.name = name
        self.portion = portion
        self.notes = notes
        self.schedule = schedule
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
        self.category = category
        self.calories = calories
        self.restrictions = restrictions
        self.mealType = mealType
    }
}

// MARK: - HealthItem Conformance
@available(iOS 18.0, *)
extension Diet {
    var itemType: HealthItemType {
        .diet
    }
    
    var displayName: String {
        name
    }
    
    // For Diet, we treat dosage as portion size
    var dosage: String {
        get { portion }
        set { portion = newValue }
    }
}

// MARK: - Diet Categories
@available(iOS 18.0, *)
extension Diet {
    enum DietCategory: String, CaseIterable, Codable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"
        case beverage = "Beverage"
        case supplement = "Nutritional Supplement"
        case special = "Special Diet"
        
        var icon: String {
            switch self {
            case .breakfast: return "sun.max.fill"
            case .lunch: return "sun.and.horizon.fill"
            case .dinner: return "moon.stars.fill"
            case .snack: return "carrot.fill"
            case .beverage: return "cup.and.saucer.fill"
            case .supplement: return "pills.fill"
            case .special: return "heart.text.square.fill"
            }
        }
    }
}

// MARK: - Meal Types
@available(iOS 18.0, *)
extension Diet {
    enum MealType: String, CaseIterable, Codable {
        case fullMeal = "Full Meal"
        case lightMeal = "Light Meal"
        case snack = "Snack"
        case drink = "Drink"
        case dessert = "Dessert"
        
        var defaultPortion: String {
            switch self {
            case .fullMeal: return "1 plate"
            case .lightMeal: return "1 bowl"
            case .snack: return "1 serving"
            case .drink: return "1 cup"
            case .dessert: return "1 piece"
            }
        }
    }
}

// MARK: - Dietary Restrictions
@available(iOS 18.0, *)
extension Diet {
    enum DietaryRestriction: String, CaseIterable, Codable {
        case lowSodium = "Low Sodium"
        case lowSugar = "Low Sugar"
        case diabeticFriendly = "Diabetic Friendly"
        case heartHealthy = "Heart Healthy"
        case glutenFree = "Gluten Free"
        case dairyFree = "Dairy Free"
        case vegetarian = "Vegetarian"
        case vegan = "Vegan"
        case lowCarb = "Low Carb"
        case lowFat = "Low Fat"
        case highProtein = "High Protein"
        case renal = "Renal Diet"
        case softFoods = "Soft Foods"
        case pureed = "Pureed"
        
        var icon: String {
            switch self {
            case .lowSodium: return "drop.halffull"
            case .lowSugar: return "cube.transparent"
            case .diabeticFriendly: return "cross.circle"
            case .heartHealthy: return "heart.fill"
            case .glutenFree: return "wheat"
            case .dairyFree: return "milk.bottle"
            case .vegetarian, .vegan: return "leaf.fill"
            case .lowCarb: return "scalemass"
            case .lowFat: return "drop"
            case .highProtein: return "figure.strengthtraining.traditional"
            case .renal: return "drop.triangle"
            case .softFoods, .pureed: return "circle.dotted"
            }
        }
    }
}

// MARK: - Validation
@available(iOS 18.0, *)
extension Diet {
    func validate() throws {
        // Use base validation from protocol
        try (self as (any HealthItem)).validate()
        
        // Portion validation
        let trimmedPortion = portion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPortion.isEmpty else {
            throw AppError.missingRequiredField(field: "portion size")
        }
        guard trimmedPortion.count <= 50 else {
            throw AppError.nameTooLong(maximum: 50)
        }
        
        // Calorie validation if present
        if let calories = calories {
            guard calories >= 0 && calories <= 5000 else {
                throw AppError.invalidSchedule(reason: "Calories must be between 0 and 5000")
            }
        }
        
        // Diet items can have 2-4 times per day (flexible meal schedules)
        let frequency = schedule.timePeriods.count + schedule.customTimes.count
        guard frequency >= 1 && frequency <= 4 else {
            throw AppError.invalidSchedule(reason: "Diet items can be scheduled 1-4 times per day")
        }
    }
}

// MARK: - Display Helpers
@available(iOS 18.0, *)
extension Diet {
    var fullDescription: String {
        var description = "\(name) - \(portion)"
        if let calories = calories {
            description += " (\(calories) cal)"
        }
        return description
    }
    
    var restrictionsSummary: String {
        guard !restrictions.isEmpty else { return "No restrictions" }
        return restrictions.map { $0.rawValue }.joined(separator: ", ")
    }
    
    var isSpecialDiet: Bool {
        !restrictions.isEmpty
    }
    
    var calorieDisplay: String {
        guard let calories = calories else { return "" }
        return "\(calories) calories"
    }
}

// MARK: - Sample Data
@available(iOS 18.0, *)
extension Diet {
    static let sampleBreakfast = Diet(
        name: "Oatmeal with berries",
        portion: "1 bowl",
        notes: "Add honey if desired",
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.breakfast]
        ),
        category: .breakfast,
        calories: 250,
        restrictions: [.diabeticFriendly, .heartHealthy],
        mealType: .fullMeal
    )
    
    static let sampleLunch = Diet(
        name: "Low-sodium soup",
        portion: "1 bowl with whole grain bread",
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.lunch]
        ),
        category: .lunch,
        calories: 350,
        restrictions: [.lowSodium, .heartHealthy],
        mealType: .fullMeal
    )
    
    static let sampleSnack = Diet(
        name: "Apple slices with almond butter",
        portion: "1 medium apple + 2 tbsp",
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.custom],
            customTimes: [Date()]
        ),
        category: .snack,
        calories: 200,
        restrictions: [.diabeticFriendly, .glutenFree],
        mealType: .snack
    )
}
