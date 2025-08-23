//
//  FirestoreModels.swift
//  HealthGuide
//
//  Firestore data models for group sharing and health data
//  Enhanced for complete Core Data to Firebase migration
//

import Foundation
import FirebaseFirestore

// MARK: - Firestore Group
struct FirestoreGroup: Codable, Identifiable {
    var documentId: String?
    let id: String
    let name: String
    let inviteCode: String
    let createdBy: String
    var adminIds: [String]
    var memberIds: [String]
    var writePermissionIds: [String]
    let createdAt: Date
    var updatedAt: Date
    var trialStartDate: Date?  // Admin's trial start date (shared with all members)
    var trialEndDate: Date?    // Admin's trial end date (shared with all members)
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "inviteCode": inviteCode,
            "createdBy": createdBy,
            "adminIds": adminIds,
            "memberIds": memberIds,
            "writePermissionIds": writePermissionIds,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let trialStart = trialStartDate {
            dict["trialStartDate"] = Timestamp(date: trialStart)
        }
        
        if let trialEnd = trialEndDate {
            dict["trialEndDate"] = Timestamp(date: trialEnd)
        }
        
        return dict
    }
}

// MARK: - Firestore Member
struct FirestoreMember: Codable, Identifiable {
    var documentId: String?
    let id: String
    let userId: String
    let groupId: String
    var name: String  // Made mutable for name editing
    var displayName: String?  // Custom name set by primary user
    var role: String // "admin" or "member"
    var permissions: String // "write" or "read"
    var isAccessEnabled: Bool  // Toggle for access control
    let joinedAt: Date
    var lastActiveAt: Date?
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "groupId": groupId,
            "name": name,
            "role": role,
            "permissions": permissions,
            "isAccessEnabled": isAccessEnabled,
            "joinedAt": Timestamp(date: joinedAt)
        ]
        
        if let displayName = displayName {
            dict["displayName"] = displayName
        }
        
        if let lastActive = lastActiveAt {
            dict["lastActiveAt"] = Timestamp(date: lastActive)
        }
        
        return dict
    }
    
    init(id: String = UUID().uuidString,
         userId: String,
         groupId: String,
         name: String,
         displayName: String? = nil,
         role: String = "member",
         permissions: String = "read",
         isAccessEnabled: Bool = true,
         joinedAt: Date = Date(),
         lastActiveAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.groupId = groupId
        self.name = name
        self.displayName = displayName
        self.role = role
        self.permissions = permissions
        self.isAccessEnabled = isAccessEnabled
        self.joinedAt = joinedAt
        self.lastActiveAt = lastActiveAt
    }
}

// MARK: - Enhanced Firestore Medication
struct FirestoreMedication: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var name: String
    var dosage: String
    var quantity: Int
    var unit: String
    var notes: String?
    var isActive: Bool
    var category: String?
    var prescribedBy: String?
    var prescriptionNumber: String?
    var refillsRemaining: Int?
    var expirationDate: Date?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var scheduleId: String?
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "name": name,
            "dosage": dosage,
            "quantity": quantity,
            "unit": unit,
            "isActive": isActive,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let notes = notes { dict["notes"] = notes }
        if let category = category { dict["category"] = category }
        if let prescribedBy = prescribedBy { dict["prescribedBy"] = prescribedBy }
        if let prescriptionNumber = prescriptionNumber { dict["prescriptionNumber"] = prescriptionNumber }
        if let refillsRemaining = refillsRemaining { dict["refillsRemaining"] = refillsRemaining }
        if let expirationDate = expirationDate { dict["expirationDate"] = Timestamp(date: expirationDate) }
        if let scheduleId = scheduleId { dict["scheduleId"] = scheduleId }
        
        return dict
    }
    
    @available(iOS 18.0, *)
    init(from medication: Medication, groupId: String, userId: String) {
        self.id = medication.id.uuidString
        self.groupId = groupId
        self.name = medication.name
        self.dosage = medication.dosage
        self.quantity = medication.quantity
        self.unit = medication.unit.rawValue
        self.notes = medication.notes
        self.isActive = medication.isActive
        self.category = medication.category?.rawValue
        self.prescribedBy = medication.prescribedBy
        self.prescriptionNumber = medication.prescriptionNumber
        self.refillsRemaining = medication.refillsRemaining
        self.expirationDate = medication.expirationDate
        self.createdBy = userId
        self.createdAt = medication.createdAt
        self.updatedAt = medication.updatedAt
    }
    
    @available(iOS 18.0, *)
    func toMedication(with schedule: Schedule? = nil) -> Medication? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        
        return Medication(
            id: uuid,
            name: name,
            dosage: dosage,
            quantity: quantity,
            unit: Medication.DosageUnit(rawValue: unit) ?? .tablet,
            notes: notes,
            schedule: schedule ?? Schedule(),
            isActive: isActive,
            category: category.flatMap { Medication.MedicationCategory(rawValue: $0) },
            prescribedBy: prescribedBy,
            prescriptionNumber: prescriptionNumber,
            refillsRemaining: refillsRemaining,
            expirationDate: expirationDate
        )
    }
}

// MARK: - Enhanced Firestore Supplement
struct FirestoreSupplement: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var name: String
    var dosage: String
    var unit: String
    var notes: String?
    var isActive: Bool
    var category: String?
    var brand: String?
    var purpose: String?
    var interactions: String?
    var quantity: Int
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var scheduleId: String?
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "name": name,
            "dosage": dosage,
            "unit": unit,
            "quantity": quantity,
            "isActive": isActive,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let notes = notes { dict["notes"] = notes }
        if let category = category { dict["category"] = category }
        if let brand = brand { dict["brand"] = brand }
        if let purpose = purpose { dict["purpose"] = purpose }
        if let interactions = interactions { dict["interactions"] = interactions }
        if let scheduleId = scheduleId { dict["scheduleId"] = scheduleId }
        
        return dict
    }
    
    @available(iOS 18.0, *)
    init(from supplement: Supplement, groupId: String, userId: String) {
        self.id = supplement.id.uuidString
        self.groupId = groupId
        self.name = supplement.name
        self.dosage = supplement.dosage
        self.unit = supplement.unit.rawValue
        self.notes = supplement.notes
        self.isActive = supplement.isActive
        self.category = supplement.category?.rawValue
        self.brand = supplement.brand
        self.purpose = supplement.purpose
        self.interactions = supplement.interactions
        self.quantity = supplement.quantity
        self.createdBy = userId
        self.createdAt = supplement.createdAt
        self.updatedAt = supplement.updatedAt
    }
    
    @available(iOS 18.0, *)
    func toSupplement(with schedule: Schedule? = nil) -> Supplement? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        
        return Supplement(
            id: uuid,
            name: name,
            dosage: dosage,
            quantity: quantity,
            unit: Supplement.SupplementUnit(rawValue: unit) ?? .tablet,
            notes: notes,
            schedule: schedule ?? Schedule(),
            isActive: isActive,
            category: category.flatMap { Supplement.SupplementCategory(rawValue: $0) },
            brand: brand,
            purpose: purpose,
            interactions: interactions
        )
    }
}

// MARK: - Enhanced Firestore Diet
struct FirestoreDiet: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var name: String
    var portion: String
    var notes: String?
    var isActive: Bool
    var category: String?
    var calories: Int?
    var restrictions: [String]?
    var mealType: String?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    var scheduleId: String?
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "name": name,
            "portion": portion,
            "isActive": isActive,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let notes = notes { dict["notes"] = notes }
        if let category = category { dict["category"] = category }
        if let calories = calories { dict["calories"] = calories }
        if let restrictions = restrictions { dict["restrictions"] = restrictions }
        if let mealType = mealType { dict["mealType"] = mealType }
        if let scheduleId = scheduleId { dict["scheduleId"] = scheduleId }
        
        return dict
    }
    
    @available(iOS 18.0, *)
    init(from diet: Diet, groupId: String, userId: String) {
        self.id = diet.id.uuidString
        self.groupId = groupId
        self.name = diet.name
        self.portion = diet.portion
        self.notes = diet.notes
        self.isActive = diet.isActive
        self.category = diet.category?.rawValue
        self.calories = diet.calories
        self.restrictions = diet.restrictions.map { $0.rawValue }
        self.mealType = diet.mealType?.rawValue
        self.createdBy = userId
        self.createdAt = diet.createdAt
        self.updatedAt = diet.updatedAt
    }
    
    @available(iOS 18.0, *)
    func toDiet(with schedule: Schedule? = nil) -> Diet? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        
        let restrictionSet = Set(restrictions?.compactMap { Diet.DietaryRestriction(rawValue: $0) } ?? [])
        
        return Diet(
            id: uuid,
            name: name,
            portion: portion,
            notes: notes,
            schedule: schedule ?? Schedule(),
            isActive: isActive,
            category: category.flatMap { Diet.DietCategory(rawValue: $0) },
            calories: calories,
            restrictions: restrictionSet,
            mealType: mealType.flatMap { Diet.MealType(rawValue: $0) }
        )
    }
}

// MARK: - Firestore Schedule
struct FirestoreSchedule: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var frequency: String
    var timePeriods: [String]
    var customTimes: [Date]
    var startDate: Date
    var endDate: Date?
    var activeDays: [Date]
    let createdBy: String
    let createdAt: Date
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "frequency": frequency,
            "timePeriods": timePeriods,
            "customTimes": customTimes.map { Timestamp(date: $0) },
            "startDate": Timestamp(date: startDate),
            "activeDays": activeDays.map { Timestamp(date: $0) },
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let endDate = endDate { dict["endDate"] = Timestamp(date: endDate) }
        
        return dict
    }
    
    @available(iOS 18.0, *)
    init(from schedule: Schedule, groupId: String, userId: String) {
        self.id = UUID().uuidString
        self.groupId = groupId
        self.frequency = schedule.frequency.rawValue
        self.timePeriods = schedule.timePeriods.map { $0.rawValue }
        self.customTimes = schedule.customTimes
        self.startDate = schedule.startDate
        self.endDate = schedule.endDate
        self.activeDays = Array(schedule.activeDays)
        self.createdBy = userId
        self.createdAt = Date()
    }
    
    @available(iOS 18.0, *)
    func toSchedule() -> Schedule {
        Schedule(
            frequency: Schedule.Frequency(rawValue: frequency) ?? .once,
            timePeriods: timePeriods.compactMap { TimePeriod(rawValue: $0) },
            customTimes: customTimes,
            startDate: startDate,
            endDate: endDate,
            activeDays: Set(activeDays)
        )
    }
}

// MARK: - Firestore Dose
struct FirestoreDose: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var medicationId: String?
    var supplementId: String?
    var dietId: String?
    var scheduledTime: Date
    var period: String
    var isTaken: Bool
    var takenAt: Date?
    var notes: String?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "scheduledTime": Timestamp(date: scheduledTime),
            "period": period,
            "isTaken": isTaken,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let medicationId = medicationId { dict["medicationId"] = medicationId }
        if let supplementId = supplementId { dict["supplementId"] = supplementId }
        if let dietId = dietId { dict["dietId"] = dietId }
        if let takenAt = takenAt { dict["takenAt"] = Timestamp(date: takenAt) }
        if let notes = notes { dict["notes"] = notes }
        
        return dict
    }
}

// MARK: - Firestore Contact
struct FirestoreContact: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var name: String
    var category: String?
    var phone: String?
    var isPrimary: Bool
    var notes: String?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "name": name,
            "isPrimary": isPrimary,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let category = category { dict["category"] = category }
        if let phone = phone { dict["phone"] = phone }
        if let notes = notes { dict["notes"] = notes }
        
        return dict
    }
}

// MARK: - Firestore Document
struct FirestoreDocument: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var filename: String
    var fileType: String
    var category: String?
    var fileSize: Int64
    var storageUrl: String? // Firebase Storage URL
    var notes: String?
    let createdBy: String
    let createdAt: Date
    var updatedAt: Date
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "filename": filename,
            "fileType": fileType,
            "fileSize": fileSize,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        
        if let category = category { dict["category"] = category }
        if let storageUrl = storageUrl { dict["storageUrl"] = storageUrl }
        if let notes = notes { dict["notes"] = notes }
        
        return dict
    }
}

// MARK: - Firestore Care Memo
struct FirestoreCareMemo: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var title: String?
    var audioStorageUrl: String? // Firebase Storage URL for audio
    var duration: Double
    var recordedAt: Date
    var transcription: String?
    var priority: String?
    var relatedMedicationIds: [String]?
    let createdBy: String
    let createdAt: Date
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "duration": duration,
            "recordedAt": Timestamp(date: recordedAt),
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let title = title { dict["title"] = title }
        if let audioStorageUrl = audioStorageUrl { dict["audioStorageUrl"] = audioStorageUrl }
        if let transcription = transcription { dict["transcription"] = transcription }
        if let priority = priority { dict["priority"] = priority }
        if let relatedMedicationIds = relatedMedicationIds { dict["relatedMedicationIds"] = relatedMedicationIds }
        
        return dict
    }
}

// MARK: - Firestore Conflict
struct FirestoreConflict: Codable, Identifiable {
    var documentId: String?
    let id: String
    let groupId: String
    var type: String
    var severity: String
    var description: String
    var affectedItems: [String]
    var resolution: String?
    var isResolved: Bool
    let createdBy: String
    let createdAt: Date
    var resolvedAt: Date?
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "groupId": groupId,
            "type": type,
            "severity": severity,
            "description": description,
            "affectedItems": affectedItems,
            "isResolved": isResolved,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let resolution = resolution { dict["resolution"] = resolution }
        if let resolvedAt = resolvedAt { dict["resolvedAt"] = Timestamp(date: resolvedAt) }
        
        return dict
    }
}

// MARK: - Conversion Helpers
extension FirestoreGroup {
    // Convert to local CareGroup model
    @available(iOS 18.0, *)
    func toCareGroup() -> CareGroup {
        var group = CareGroup(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            adminUserID: UUID(uuidString: createdBy) ?? UUID(),
            settings: GroupSettings.default
        )
        // Set the invite code and dates after initialization
        group.inviteCode = inviteCode
        group.updatedAt = updatedAt
        return group
    }
}

extension FirestoreMember {
    // Convert to local GroupMember model
    @available(iOS 18.0, *)
    func toGroupMember() -> GroupMember {
        // Parse role and permissions from string values
        let memberRole: MemberRole = switch role.lowercased() {
        case "admin": .admin
        case "caregiver": .caregiver
        default: .member
        }
        
        let memberPermissions: MemberPermissions = switch permissions.lowercased() {
        case "write", "fullaccess": .fullAccess
        case "edithealth": .editHealth
        default: .readOnly
        }
        
        var member = GroupMember(
            id: UUID(uuidString: id) ?? UUID(),
            userID: UUID(uuidString: userId) ?? UUID(),
            name: name,
            email: nil,
            phoneNumber: nil,
            role: memberRole,
            permissions: memberPermissions
        )
        
        // Update timestamps after initialization
        if let lastActive = lastActiveAt {
            member.lastActiveAt = lastActive
        }
        
        return member
    }
}

// MARK: - Helper Extensions for Document Snapshot Initialization

extension FirestoreMedication {
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        guard let id = data["id"] as? String,
              let groupId = data["groupId"] as? String,
              let name = data["name"] as? String,
              let dosage = data["dosage"] as? String,
              let quantity = data["quantity"] as? Int,
              let unit = data["unit"] as? String,
              let isActive = data["isActive"] as? Bool,
              let createdBy = data["createdBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.documentId = document.documentID
        self.id = id
        self.groupId = groupId
        self.name = name
        self.dosage = dosage
        self.quantity = quantity
        self.unit = unit
        self.notes = data["notes"] as? String
        self.isActive = isActive
        self.category = data["category"] as? String
        self.prescribedBy = data["prescribedBy"] as? String
        self.prescriptionNumber = data["prescriptionNumber"] as? String
        self.refillsRemaining = data["refillsRemaining"] as? Int
        self.expirationDate = (data["expirationDate"] as? Timestamp)?.dateValue()
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduleId = data["scheduleId"] as? String
    }
}

extension FirestoreSupplement {
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        guard let id = data["id"] as? String,
              let groupId = data["groupId"] as? String,
              let name = data["name"] as? String,
              let dosage = data["dosage"] as? String,
              let unit = data["unit"] as? String,
              let quantity = data["quantity"] as? Int,
              let isActive = data["isActive"] as? Bool,
              let createdBy = data["createdBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.documentId = document.documentID
        self.id = id
        self.groupId = groupId
        self.name = name
        self.dosage = dosage
        self.unit = unit
        self.notes = data["notes"] as? String
        self.isActive = isActive
        self.category = data["category"] as? String
        self.brand = data["brand"] as? String
        self.purpose = data["purpose"] as? String
        self.interactions = data["interactions"] as? String
        self.quantity = quantity
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduleId = data["scheduleId"] as? String
    }
}

extension FirestoreDiet {
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        guard let id = data["id"] as? String,
              let groupId = data["groupId"] as? String,
              let name = data["name"] as? String,
              let portion = data["portion"] as? String,
              let isActive = data["isActive"] as? Bool,
              let createdBy = data["createdBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.documentId = document.documentID
        self.id = id
        self.groupId = groupId
        self.name = name
        self.portion = portion
        self.notes = data["notes"] as? String
        self.isActive = isActive
        self.category = data["category"] as? String
        self.calories = data["calories"] as? Int
        self.restrictions = data["restrictions"] as? [String]
        self.mealType = data["mealType"] as? String
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduleId = data["scheduleId"] as? String
    }
}

extension FirestoreDose {
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        guard let id = data["id"] as? String,
              let groupId = data["groupId"] as? String,
              let scheduledTime = (data["scheduledTime"] as? Timestamp)?.dateValue(),
              let period = data["period"] as? String,
              let isTaken = data["isTaken"] as? Bool,
              let createdBy = data["createdBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.documentId = document.documentID
        self.id = id
        self.groupId = groupId
        self.medicationId = data["medicationId"] as? String
        self.supplementId = data["supplementId"] as? String
        self.dietId = data["dietId"] as? String
        self.scheduledTime = scheduledTime
        self.period = period
        self.isTaken = isTaken
        self.takenAt = (data["takenAt"] as? Timestamp)?.dateValue()
        self.notes = data["notes"] as? String
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension FirestoreSchedule {
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        guard let id = data["id"] as? String,
              let groupId = data["groupId"] as? String,
              let frequency = data["frequency"] as? String,
              let timePeriods = data["timePeriods"] as? [String],
              let createdBy = data["createdBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let startDate = (data["startDate"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.documentId = document.documentID
        self.id = id
        self.groupId = groupId
        self.frequency = frequency
        self.timePeriods = timePeriods
        self.customTimes = (data["customTimes"] as? [Timestamp])?.map { $0.dateValue() } ?? []
        self.startDate = startDate
        self.endDate = (data["endDate"] as? Timestamp)?.dateValue()
        self.activeDays = (data["activeDays"] as? [Timestamp])?.map { $0.dateValue() } ?? []
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}

extension FirestoreContact {
    init?(from document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        guard let id = data["id"] as? String,
              let groupId = data["groupId"] as? String,
              let name = data["name"] as? String,
              let isPrimary = data["isPrimary"] as? Bool,
              let createdBy = data["createdBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        
        self.documentId = document.documentID
        self.id = id
        self.groupId = groupId
        self.name = name
        self.category = data["category"] as? String
        self.phone = data["phone"] as? String
        self.isPrimary = isPrimary
        self.notes = data["notes"] as? String
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}