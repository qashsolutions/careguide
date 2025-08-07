//
//  ContactEntity+Extensions.swift
//  HealthGuide
//
//  Extensions for ContactEntity with CloudKit default values
//  Production-ready implementation for healthcare contact management
//

import Foundation
import CoreData
import SwiftUI

@available(iOS 18.0, *)
extension ContactEntity {
    
    // MARK: - Contact Categories
    public enum ContactCategory: String, CaseIterable, Sendable {
        case doctor = "Doctor"
        case pharmacy = "Pharmacy"
        case caregiver = "Caregiver"
        case nurse = "Nurse"
        case therapist = "Therapist"
        case specialist = "Specialist"
        case emergency = "Emergency"
        case other = "Other"
        
        /// Default category for new contacts
        static let defaultCategory = ContactCategory.other
        
        /// Icon for UI display
        var iconName: String {
            switch self {
            case .doctor: return "stethoscope"
            case .pharmacy: return "pills.fill"
            case .caregiver: return "person.2.fill"
            case .nurse: return "cross.case.fill"
            case .therapist: return "brain.head.profile"
            case .specialist: return "star.fill"
            case .emergency: return "staroflife.fill"
            case .other: return "person.fill"
            }
        }
        
        /// Color for UI display
        var colorName: String {
            switch self {
            case .doctor: return "blue"
            case .pharmacy: return "green"
            case .caregiver: return "purple"
            case .nurse: return "pink"
            case .therapist: return "orange"
            case .specialist: return "indigo"
            case .emergency: return "red"
            case .other: return "gray"
            }
        }
        
        /// SwiftUI Color
        var color: Color {
            return Color(colorName)
        }
        
        /// Sort priority (lower number = higher priority)
        var sortPriority: Int {
            switch self {
            case .emergency: return 0
            case .doctor: return 1
            case .specialist: return 2
            case .pharmacy: return 3
            case .nurse: return 4
            case .therapist: return 5
            case .caregiver: return 6
            case .other: return 7
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
            print("📞 ContactEntity: Generated ID: \(id!)")
            #endif
        }
        
        // Set required string fields to empty if nil
        if name == nil {
            name = ""
            #if DEBUG
            print("📝 ContactEntity: Set empty name")
            #endif
        }
        
        if phone == nil {
            phone = ""
            #if DEBUG
            print("📱 ContactEntity: Set empty phone")
            #endif
        }
        
        // Note: email, displayName, and createdAt don't exist in ContactEntity
        // We only have: id, name, category, phone, isPrimary, notes
        
        // Validate existing values
        validateAndFixData()
        
        #if DEBUG
        print("✅ ContactEntity: awakeFromInsert completed")
        #endif
    }
    
    // MARK: - Validation Methods
    
    /// Validates and fixes data integrity
    private func validateAndFixData() {
        // Validate category if set
        if let currentCategory = category, !currentCategory.isEmpty {
            let validCategories = ContactCategory.allCases.map { $0.rawValue }
            if !validCategories.contains(currentCategory) {
                let oldValue = currentCategory
                category = ContactCategory.defaultCategory.rawValue
                
                #if DEBUG
                print("⚠️ ContactEntity: Invalid category '\(oldValue)' fixed to '\(category!)'")
                #endif
                
                // Post notification for error tracking
                NotificationCenter.default.post(
                    name: .coreDataEntityError,
                    object: nil,
                    userInfo: [
                        "entity": "ContactEntity",
                        "field": "category",
                        "error": "Invalid category value: \(oldValue)",
                        "fallbackValue": category!,
                        "action": "validation_fix"
                    ]
                )
            }
        }
        
        // Validate phone number format
        if let currentPhone = phone, !currentPhone.isEmpty {
            phone = sanitizePhoneNumber(currentPhone)
        }
    }
    
    /// Sanitize phone number for consistent storage
    private func sanitizePhoneNumber(_ phoneNumber: String) -> String {
        // Remove common formatting characters but keep + for international
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
        let filtered = phoneNumber.unicodeScalars.filter { allowedCharacters.contains($0) }
        let sanitized = String(String.UnicodeScalarView(filtered))
        
        if sanitized != phoneNumber {
            #if DEBUG
            print("📱 ContactEntity: Sanitized phone from '\(phoneNumber)' to '\(sanitized)'")
            #endif
        }
        
        return sanitized
    }
    
    // MARK: - Helper Methods
    
    /// Set category with validation
    public func setCategory(_ newCategory: ContactCategory) {
        category = newCategory.rawValue
        #if DEBUG
        print("🏷️ ContactEntity: Updated category to \(newCategory.rawValue)")
        #endif
    }
    
    /// Get category as enum
    public var contactCategory: ContactCategory? {
        guard let category = category else { return nil }
        return ContactCategory(rawValue: category)
    }
    
    /// Get category color for SwiftUI
    public var categoryColor: Color {
        return contactCategory?.color ?? Color.gray
    }
    
    /// Get category icon name
    public var categoryIconName: String {
        return contactCategory?.iconName ?? "person.fill"
    }
    
    /// Set as primary contact
    public func setAsPrimary(_ primary: Bool) {
        isPrimary = primary
        #if DEBUG
        print("⭐ ContactEntity: Set primary status to \(primary)")
        #endif
    }
    
    /// Format phone number for display
    public var formattedPhone: String {
        guard let phone = phone, !phone.isEmpty else { return "" }
        
        // Basic US phone formatting
        if phone.count == 10 && !phone.hasPrefix("+") {
            let areaCode = phone.prefix(3)
            let prefix = phone.dropFirst(3).prefix(3)
            let lineNumber = phone.dropFirst(6)
            return "(\(areaCode)) \(prefix)-\(lineNumber)"
        } else if phone.count == 11 && phone.hasPrefix("1") {
            let withoutCountry = phone.dropFirst()
            let areaCode = withoutCountry.prefix(3)
            let prefix = withoutCountry.dropFirst(3).prefix(3)
            let lineNumber = withoutCountry.dropFirst(6)
            return "+1 (\(areaCode)) \(prefix)-\(lineNumber)"
        }
        
        // Return as-is for international or non-standard formats
        return phone
    }
    
    /// Get display name with fallback
    public var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        } else if let category = contactCategory {
            return "Unnamed \(category.rawValue)"
        } else {
            return "Unnamed Contact"
        }
    }
    
    /// Get initials for avatar
    public var initials: String {
        guard let name = name, !name.isEmpty else {
            // Use category initial if no name
            return String(contactCategory?.rawValue.prefix(1) ?? "?").uppercased()
        }
        
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            let first = components.first?.prefix(1) ?? ""
            let last = components.last?.prefix(1) ?? ""
            return "\(first)\(last)".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    /// Check if contact has complete information
    public var isComplete: Bool {
        guard let name = name, !name.isEmpty,
              let phone = phone, !phone.isEmpty else {
            return false
        }
        return true
    }
    
    /// Get sort priority based on category and primary status
    public var sortPriority: Int {
        var priority = contactCategory?.sortPriority ?? 999
        // Primary contacts get higher priority
        if isPrimary == true {
            priority -= 100
        }
        return priority
    }
    
    /// Create a callable phone URL
    public var phoneURL: URL? {
        guard let phone = phone, !phone.isEmpty else { return nil }
        let cleanedPhone = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        return URL(string: "tel://\(cleanedPhone)")
    }
    
    /// Search helper - check if contact matches search term
    public func matches(searchTerm: String) -> Bool {
        let lowercasedSearch = searchTerm.lowercased()
        
        // Check name
        if let name = name?.lowercased(), name.contains(lowercasedSearch) {
            return true
        }
        
        // Check phone
        if let phone = phone, phone.contains(searchTerm) {
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
}