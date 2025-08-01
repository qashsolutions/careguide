//
//  Supplement.swift
//  HealthGuide
//
//  Supplement model extending HealthItem protocol
//  Natural health products, vitamins, minerals
//

import Foundation
import SwiftUI

@available(iOS 18.0, *)
struct Supplement: HealthItem, Sendable {
    let id: UUID
    var name: String
    var dosage: String
    var quantity: Int
    var unit: SupplementUnit
    var notes: String?
    var schedule: Schedule
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Supplement-specific properties
    var category: SupplementCategory?
    var brand: String?
    var purpose: String?
    var interactions: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        quantity: Int = 1,
        unit: SupplementUnit = .capsule,
        notes: String? = nil,
        schedule: Schedule = Schedule(),
        isActive: Bool = true,
        category: SupplementCategory? = nil,
        brand: String? = nil,
        purpose: String? = nil,
        interactions: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
        self.schedule = schedule
        self.isActive = isActive
        self.createdAt = Date()
        self.updatedAt = Date()
        self.category = category
        self.brand = brand
        self.purpose = purpose
        self.interactions = interactions
    }
}

// MARK: - HealthItem Conformance
@available(iOS 18.0, *)
extension Supplement {
    var itemType: HealthItemType {
        .supplement
    }
    
    var displayName: String {
        "\(name) \(dosage)"
    }
}

// MARK: - Supplement Units
@available(iOS 18.0, *)
extension Supplement {
    enum SupplementUnit: String, CaseIterable, Codable {
        case capsule = "capsule"
        case softgel = "softgel"
        case tablet = "tablet"
        case gummy = "gummy"
        case powder = "scoop"
        case liquid = "ml"
        case drop = "drop"
        case spray = "spray"
        case lozenge = "lozenge"
        
        var pluralName: String {
            switch self {
            case .capsule: return "capsules"
            case .softgel: return "softgels"
            case .tablet: return "tablets"
            case .gummy: return "gummies"
            case .powder: return "scoops"
            case .liquid: return "ml"
            case .drop: return "drops"
            case .spray: return "sprays"
            case .lozenge: return "lozenges"
            }
        }
        
        func displayString(for quantity: Int) -> String {
            switch self {
            case .liquid:
                return rawValue  // ml doesn't change
            default:
                return quantity == 1 ? rawValue : pluralName
            }
        }
    }
}

// MARK: - Supplement Categories
@available(iOS 18.0, *)
extension Supplement {
    enum SupplementCategory: String, CaseIterable, Codable {
        case vitamin = "Vitamin"
        case mineral = "Mineral"
        case herb = "Herbal"
        case omega = "Omega Fatty Acids"
        case probiotic = "Probiotic"
        case antioxidant = "Antioxidant"
        case aminoAcid = "Amino Acid"
        case enzyme = "Enzyme"
        case jointHealth = "Joint Health"
        case immune = "Immune Support"
        case energy = "Energy"
        case sleep = "Sleep Support"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .vitamin: return "leaf.circle.fill"
            case .mineral: return "drop.triangle.fill"
            case .herb: return "leaf.fill"
            case .omega: return "drop.fill"
            case .probiotic: return "bacteria.fill"
            case .antioxidant: return "shield.lefthalf.filled"
            case .aminoAcid: return "molecule.fill"
            case .enzyme: return "sparkles"
            case .jointHealth: return "figure.walk"
            case .immune: return "cross.fill"
            case .energy: return "bolt.fill"
            case .sleep: return "moon.fill"
            case .other: return "pills.fill"
            }
        }
    }
}

// MARK: - Validation
@available(iOS 18.0, *)
extension Supplement {
    func validate() throws {
        // Use base validation from protocol
        try (self as (any HealthItem)).validate()
        
        // Dosage validation
        let trimmedDosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDosage.count >= Configuration.Validation.minimumDosageLength else {
            throw AppError.invalidDosage(medication: name)
        }
        guard trimmedDosage.count <= Configuration.Validation.maximumDosageLength else {
            throw AppError.nameTooLong(maximum: Configuration.Validation.maximumDosageLength)
        }
        
        // Quantity validation
        guard quantity > 0 else {
            throw AppError.invalidDosage(medication: name)
        }
        
        // Brand validation if present
        if let brand = brand, brand.count > 50 {
            throw AppError.nameTooLong(maximum: 50)
        }
    }
}

// MARK: - Display Helpers
@available(iOS 18.0, *)
extension Supplement {
    var fullDosageDescription: String {
        "\(quantity) \(unit.displayString(for: quantity))"
    }
    
    var fullDisplayName: String {
        if let brand = brand {
            return "\(brand) \(name) \(dosage)"
        }
        return displayName
    }
    
    var hasInteractionWarning: Bool {
        interactions != nil && !interactions!.isEmpty
    }
}

// MARK: - Sample Data
@available(iOS 18.0, *)
extension Supplement {
    static let sampleVitaminD = Supplement(
        name: "Vitamin D",
        dosage: "1000 IU",
        quantity: 1,
        unit: .capsule,
        notes: "Take with fatty meal for better absorption",
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.lunch]
        ),
        category: .vitamin,
        brand: "Nature's Way",
        purpose: "Bone health and immune support"
    )
    
    static let sampleOmega3 = Supplement(
        name: "Omega-3",
        dosage: "1000mg",
        quantity: 1,
        unit: .softgel,
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.lunch]
        ),
        category: .omega,
        brand: "Nordic Naturals",
        purpose: "Heart and brain health"
    )
    
    static let sampleProbiotics = Supplement(
        name: "Probiotics",
        dosage: "10 Billion CFU",
        quantity: 1,
        unit: .capsule,
        notes: "Take on empty stomach",
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.breakfast]
        ),
        category: .probiotic,
        brand: "Garden of Life",
        purpose: "Digestive and immune health"
    )
}
