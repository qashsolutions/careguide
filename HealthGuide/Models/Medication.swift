//
//  Medication.swift
//  HealthGuide
//
//  Core medication model with validation rules
//  Implements HealthItem protocol
//

import Foundation
import SwiftUI

@available(iOS 18.0, *)
struct Medication: HealthItem, Sendable {
    let id: UUID
    var name: String
    var dosage: String
    var quantity: Int
    var unit: DosageUnit
    var notes: String?
    var schedule: Schedule
    var isActive: Bool
    let createdAt: Date
    var updatedAt: Date
    
    // Medication-specific properties
    var category: MedicationCategory?
    var prescribedBy: String?
    var prescriptionNumber: String?
    var refillsRemaining: Int?
    var expirationDate: Date?
    
    init(
        id: UUID = UUID(),
        name: String,
        dosage: String,
        quantity: Int = 1,
        unit: DosageUnit = .tablet,
        notes: String? = nil,
        schedule: Schedule = Schedule(),
        isActive: Bool = true,
        category: MedicationCategory? = nil,
        prescribedBy: String? = nil,
        prescriptionNumber: String? = nil,
        refillsRemaining: Int? = nil,
        expirationDate: Date? = nil
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
        self.prescribedBy = prescribedBy
        self.prescriptionNumber = prescriptionNumber
        self.refillsRemaining = refillsRemaining
        self.expirationDate = expirationDate
    }
}

// MARK: - HealthItem Conformance
@available(iOS 18.0, *)
extension Medication {
    var itemType: HealthItemType {
        .medication
    }
    
    var displayName: String {
        "\(name) \(dosage)"
    }
}

// MARK: - Dosage Units
@available(iOS 18.0, *)
extension Medication {
    enum DosageUnit: String, CaseIterable, Codable {
        case tablet = "tablet"
        case capsule = "capsule"
        case ml = "ml"
        case mg = "mg"
        case mcg = "mcg"
        case unit = "unit"
        case drop = "drop"
        case patch = "patch"
        case inhaler = "puff"
        
        var pluralName: String {
            switch self {
            case .tablet: return "tablets"
            case .capsule: return "capsules"
            case .ml: return "ml"
            case .mg: return "mg"
            case .mcg: return "mcg"
            case .unit: return "units"
            case .drop: return "drops"
            case .patch: return "patches"
            case .inhaler: return "puffs"
            }
        }
        
        func displayString(for quantity: Int) -> String {
            quantity == 1 ? rawValue : pluralName
        }
    }
}

// MARK: - Medication Categories
@available(iOS 18.0, *)
extension Medication {
    enum MedicationCategory: String, CaseIterable, Codable {
        case diabetes = "Diabetes"
        case bloodPressure = "Blood Pressure"
        case heartHealth = "Heart Health"
        case cholesterol = "Cholesterol"
        case pain = "Pain Relief"
        case antibiotic = "Antibiotic"
        case vitamin = "Vitamin"
        case mentalHealth = "Mental Health"
        case allergy = "Allergy"
        case digestive = "Digestive"
        case respiratory = "Respiratory"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .diabetes: return "drop.fill"
            case .bloodPressure: return "heart.text.square.fill"
            case .heartHealth: return "heart.fill"
            case .cholesterol: return "chart.line.uptrend.xyaxis"
            case .pain: return "bandage.fill"
            case .antibiotic: return "shield.fill"
            case .vitamin: return "leaf.fill"
            case .mentalHealth: return "brain"
            case .allergy: return "allergens"
            case .digestive: return "stomach"
            case .respiratory: return "lungs.fill"
            case .other: return "pills.fill"
            }
        }
    }
}

// MARK: - Validation
@available(iOS 18.0, *)
extension Medication {
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
        
        // Check expiration if set
        if let expirationDate = expirationDate {
            guard expirationDate > Date() else {
                throw AppError.invalidSchedule(reason: "Medication has expired")
            }
        }
    }
}

// MARK: - Display Helpers
@available(iOS 18.0, *)
extension Medication {
    var fullDosageDescription: String {
        "\(quantity) \(unit.displayString(for: quantity))"
    }
    
    var isExpired: Bool {
        guard let expirationDate = expirationDate else { return false }
        return expirationDate < Date()
    }
    
    var needsRefill: Bool {
        guard let refills = refillsRemaining else { return false }
        return refills <= 1
    }
    
    var daysUntilExpiration: Int? {
        guard let expirationDate = expirationDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return components.day
    }
}

// MARK: - Sample Data
@available(iOS 18.0, *)
extension Medication {
    static let sampleMetformin = Medication(
        name: "Metformin",
        dosage: "500mg",
        quantity: 1,
        unit: .tablet,
        notes: "Take with food",
        schedule: Schedule(
            frequency: .twice,
            timePeriods: [.breakfast, .dinner]
        ),
        category: .diabetes,
        prescribedBy: "Dr. Smith"
    )
    
    static let sampleLisinopril = Medication(
        name: "Lisinopril",
        dosage: "10mg",
        quantity: 1,
        unit: .tablet,
        schedule: Schedule(
            frequency: .once,
            timePeriods: [.dinner]
        ),
        category: .bloodPressure,
        prescribedBy: "Dr. Johnson"
    )
}
