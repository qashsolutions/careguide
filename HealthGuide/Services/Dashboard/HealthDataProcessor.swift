//  HealthGuide/Services/Dashboard/HealthDataProcessor.swift
//  Business logic for processing and organizing health items for dashboard display
//  Swift 6 compliant with proper async/await and actor isolation
import Foundation

// MARK: - Health Data Processor
/// Singleton service responsible for fetching, processing, and organizing health data
/// Acts as the single source of truth for all health data in the app
/// Now supports both Core Data and Firebase data sources
@available(iOS 18.0, *)
actor HealthDataProcessor {
    
    // MARK: - Singleton
    static let shared = HealthDataProcessor()
    
    // MARK: - Dependencies
    private let coreDataManager = CoreDataManager.shared
    // Firebase services are MainActor isolated, so we'll access them through MainActor
    
    // MARK: - Cache
    private var cachedData: ProcessedHealthData?
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour
    private var isCurrentlyFetching = false
    
    // MARK: - Supporting Types
    
    // DoseRecord is defined in CoreDataManager+Schedule.swift at the file level
    // Just import and use it directly
    
    // MARK: - Data Processing Result
    struct ProcessedHealthData: Sendable {
        let items: [(item: any HealthItem, dose: ScheduledDose?)]
        let periodCounts: [TimePeriod: Int]
        let lastUpdated: Date
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🏥 HealthDataProcessor singleton initialized")
    }
    
    // MARK: - Public Methods
    
    /// Get health data with caching - returns cached data if valid, otherwise fetches fresh
    /// - Parameter forceRefresh: Bypass cache and fetch fresh data
    /// - Returns: Processed health data organized by time periods
    func getHealthData(forceRefresh: Bool = false) async throws -> ProcessedHealthData {
        // Return cached data if valid and not forcing refresh
        if !forceRefresh,
           let cached = cachedData,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheValidityDuration {
            AppLogger.main.info("📦 Returning cached health data (age: \(Int(Date().timeIntervalSince(lastFetch)))s)")
            return cached
        }
        
        // Prevent concurrent fetches
        guard !isCurrentlyFetching else {
            AppLogger.main.info("⏳ Fetch already in progress, waiting for completion...")
            // Wait for current fetch to complete and return cached data
            while isCurrentlyFetching {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            if let cached = cachedData {
                return cached
            }
            throw AppError.coreDataFetchFailed
        }
        
        // Fetch fresh data
        return try await fetchFreshData()
    }
    
    /// Force refresh data from source (Firebase or CoreData)
    func refreshData() async throws -> ProcessedHealthData {
        return try await getHealthData(forceRefresh: true)
    }
    
    /// Internal method to fetch fresh data
    private func fetchFreshData() async throws -> ProcessedHealthData {
        isCurrentlyFetching = true
        defer { isCurrentlyFetching = false }
        
        AppLogger.main.info("🔄 Fetching fresh health data...")
        
        let data = try await processHealthDataForToday()
        
        // Update cache
        cachedData = data
        lastFetchTime = Date()
        
        AppLogger.main.info("✅ Health data cache updated")
        return data
    }
    
    /// Fetch and process all health items for today's dashboard display
    /// - Returns: Processed health data organized by time periods
    private func processHealthDataForToday() async throws -> ProcessedHealthData {
        // Check if user is in a Firebase group
        let isInGroup = await MainActor.run { FirebaseGroupService.shared.currentGroup != nil }
        
        // Fetch data based on group membership
        let (medicationList, supplementList, dietItemList, doseRecords): ([Medication], [Supplement], [Diet], [DoseRecord])
        
        if isInGroup {
            // Fetch from Firebase when in a group
            AppLogger.main.info("📊 Fetching health data from Firebase (group mode)")
            (medicationList, supplementList, dietItemList, doseRecords) = try await fetchFromFirebase()
        } else {
            // Fetch from Core Data when not in a group
            AppLogger.main.info("📊 Fetching health data from Core Data (local mode)")
            async let medications = coreDataManager.fetchMedications()
            async let supplements = coreDataManager.fetchSupplements()
            async let dietItems = coreDataManager.fetchDietItems()
            async let allDoseRecords = coreDataManager.fetchDosesForDate(Date())
            (medicationList, supplementList, dietItemList, doseRecords) = try await (medications, supplements, dietItems, allDoseRecords)
        }
        
        // Disabled debug logging to reduce overhead
        // #if DEBUG
        // print("🏥 HealthDataProcessor: Fetched \(medicationList.count) medications, \(supplementList.count) supplements, \(dietItemList.count) diet items, \(doseRecords.count) doses")
        // #endif
        
        // Process each type of health item with their persisted doses
        var allItems: [(item: any HealthItem, dose: ScheduledDose?)] = []
        
        // Process medications with their persisted doses
        for medication in medicationList {
            let medicationDoses = doseRecords.filter { $0.itemType == "medication" && $0.itemId == medication.id }
            if medicationDoses.isEmpty {
                // If no doses found, add without dose (shouldn't happen in production)
                allItems.append((item: medication, dose: nil))
            } else {
                for doseRecord in medicationDoses {
                    let scheduledDose = convertDoseRecordToScheduledDose(doseRecord)
                    allItems.append((item: medication, dose: scheduledDose))
                }
            }
        }
        
        // Process supplements with their persisted doses
        for supplement in supplementList {
            let supplementDoses = doseRecords.filter { $0.itemType == "supplement" && $0.itemId == supplement.id }
            if supplementDoses.isEmpty {
                allItems.append((item: supplement, dose: nil))
            } else {
                for doseRecord in supplementDoses {
                    let scheduledDose = convertDoseRecordToScheduledDose(doseRecord)
                    allItems.append((item: supplement, dose: scheduledDose))
                }
            }
        }
        
        // Process diet items with their persisted doses
        for dietItem in dietItemList {
            let dietDoses = doseRecords.filter { $0.itemType == "diet" && $0.itemId == dietItem.id }
            if dietDoses.isEmpty {
                allItems.append((item: dietItem, dose: nil))
            } else {
                for doseRecord in dietDoses {
                    let scheduledDose = convertDoseRecordToScheduledDose(doseRecord)
                    allItems.append((item: dietItem, dose: scheduledDose))
                }
            }
        }
        
        // Sort items by scheduled time for optimal user experience
        let sortedItems = sortItemsByTime(allItems)
        
        // Calculate period counts for UI badge display
        let periodCounts = calculatePeriodCounts(from: sortedItems)
        
        return ProcessedHealthData(
            items: sortedItems,
            periodCounts: periodCounts,
            lastUpdated: Date()
        )
    }
    
    /// Clear the cache (useful when group changes or data is modified)
    func invalidateCache() {
        cachedData = nil
        lastFetchTime = nil
        AppLogger.main.info("🗑️ Health data cache invalidated")
    }
    
    /// Mark a specific dose as taken and return updated data
    /// - Parameters:
    ///   - itemId: ID of the health item
    ///   - doseId: ID of the specific dose
    /// - Returns: Updated processed health data
    func markDoseTakenAndRefresh(itemId: UUID, doseId: UUID, firebaseDoseId: String? = nil) async throws -> ProcessedHealthData {
        // Check if we're in Firebase mode
        if await FirebaseGroupService.shared.currentGroup != nil {
            // Sync with Firebase - use the Firebase dose ID if available
            let itemName = await getItemName(for: itemId)
            let doseIdToUse = firebaseDoseId ?? doseId.uuidString
            
            print("🔥 Marking dose as taken in Firebase - Item: \(itemName), DoseId: \(doseIdToUse)")
            try await FirebaseGroupDataService.shared.markDoseTaken(
                doseId: doseIdToUse,
                itemName: itemName
            )
            print("✅ Dose marked as taken in Firebase")
            
            // Invalidate cache to force refresh from Firebase
            invalidateCache()
            
            // Wait a moment for Firebase to propagate the change
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        } else {
            // Local Core Data mode
            // Try to find the item in our current data
            async let medications = coreDataManager.fetchMedications()
            async let supplements = coreDataManager.fetchSupplements()
            async let dietItems = coreDataManager.fetchDietItems()
            
            let (medicationList, supplementList, dietItemList) = try await (medications, supplements, dietItems)
            
            // Find which type this item belongs to and mark the dose
            if medicationList.contains(where: { $0.id == itemId }) {
                try await coreDataManager.markDoseTaken(forMedicationId: itemId, doseId: doseId)
            } else if supplementList.contains(where: { $0.id == itemId }) {
                try await coreDataManager.markDoseTaken(forSupplementId: itemId, doseId: doseId)
            } else if dietItemList.contains(where: { $0.id == itemId }) {
                try await coreDataManager.markDoseTaken(forDietId: itemId, doseId: doseId)
            } else {
                throw AppError.coreDataFetchFailed
            }
        }
        
        // Force refresh to get updated data
        return try await getHealthData(forceRefresh: true)
    }
    
    /// Helper to get item name for Firebase sync
    private func getItemName(for itemId: UUID) async -> String {
        // Try medications first
        if let medications = try? await coreDataManager.fetchMedications(),
           let med = medications.first(where: { $0.id == itemId }) {
            return med.name
        }
        
        // Try supplements
        if let supplements = try? await coreDataManager.fetchSupplements(),
           let sup = supplements.first(where: { $0.id == itemId }) {
            return sup.name
        }
        
        // Try diet items
        if let diets = try? await coreDataManager.fetchDietItems(),
           let diet = diets.first(where: { $0.id == itemId }) {
            return diet.name
        }
        
        return "Unknown Item"
    }
    
    // MARK: - Private Processing Methods
    
    /// Convert DoseRecord to ScheduledDose
    private func convertDoseRecordToScheduledDose(_ record: DoseRecord) -> ScheduledDose {
        // Convert string period to TimePeriod enum
        let period = TimePeriod(rawValue: record.period) ?? .breakfast
        return ScheduledDose(
            id: record.id,
            time: record.scheduledTime,
            period: period,
            isTaken: record.isTaken,
            takenAt: record.takenAt,
            firebaseDoseId: record.firebaseDoseId  // Pass through the Firebase document ID
        )
    }
    
    /// Sort health items by their scheduled time for chronological display
    /// - Parameter items: Unsorted array of health items with doses
    /// - Returns: Array sorted by time (earliest first)
    private func sortItemsByTime(_ items: [(item: any HealthItem, dose: ScheduledDose?)]) -> [(item: any HealthItem, dose: ScheduledDose?)] {
        return items.sorted { first, second in
            let firstTime = first.dose?.time ?? Date.distantFuture
            let secondTime = second.dose?.time ?? Date.distantFuture
            return firstTime < secondTime
        }
    }
    
    /// Calculate the number of items scheduled for each time period
    /// - Parameter items: Processed health items with doses
    /// - Returns: Dictionary mapping time periods to item counts
    private func calculatePeriodCounts(from items: [(item: any HealthItem, dose: ScheduledDose?)]) -> [TimePeriod: Int] {
        var counts: [TimePeriod: Int] = [
            .breakfast: 0,
            .lunch: 0,
            .dinner: 0
        ]
        
        for item in items {
            if let period = item.dose?.period {
                counts[period, default: 0] += 1
            }
        }
        
        return counts
    }
}

// MARK: - Time Period Utilities
@available(iOS 18.0, *)
extension HealthDataProcessor {
    
    /// Determine the current time period based on the current hour
    /// - Returns: Current time period for highlighting in UI
    static func getCurrentTimePeriod() -> TimePeriod {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Extended time windows to match actual usage patterns:
        // Breakfast: 6 AM - 11 AM (5 hours)
        // Lunch: 12 PM - 3 PM (3 hours)
        // Dinner: 5 PM - 8 PM (3 hours)
        
        switch hour {
        case 6..<11:
            return .breakfast   // 6 AM - 11 AM
        case 12..<15:
            return .lunch       // 12 PM - 3 PM (noon to 3 PM)
        case 17..<20:
            return .dinner      // 5 PM - 8 PM
        default:
            // Outside medication windows, return the nearest/most logical period
            if hour < 6 {
                return .breakfast   // Early morning -> breakfast coming
            } else if hour == 11 {
                return .breakfast   // Still breakfast until noon
            } else if hour >= 15 && hour < 17 {
                return .lunch       // 3-5 PM still lunch period
            } else if hour >= 20 {
                return .dinner      // After 8 PM -> still dinner period
            } else {
                // This shouldn't happen, but default to lunch for midday
                return .lunch
            }
        }
    }
    
    /// Get all available time periods in display order
    /// - Returns: Array of time periods for UI display
    static func getAllTimePeriods() -> [TimePeriod] {
        return [.breakfast, .lunch, .dinner]
    }
    
    // MARK: - Firebase Integration
    
    /// Fetch health data from Firebase when in a group
    private func fetchFromFirebase() async throws -> ([Medication], [Supplement], [Diet], [DoseRecord]) {
        // Fetch from Firebase group space - all members see the same data
        let firestoreMeds = try await FirebaseGroupDataService.shared.fetchAllMedications()
        
        let firestoreSups = try await FirebaseGroupDataService.shared.fetchAllSupplements()
        
        let firestoreDiets = try await FirebaseGroupDataService.shared.fetchAllDiets()
        
        // Fetch today's doses from Firebase
        let firestoreDoses = try await FirebaseGroupDataService.shared.fetchTodaysDoses()
        
        // Convert Firestore models to local models
        // The schedule is now reconstructed from the stored data in toMedication/toSupplement
        let medications = firestoreMeds.compactMap { firestoreMed in
            return firestoreMed.toMedication()
        }
        
        let supplements = firestoreSups.compactMap { firestoreSup in
            return firestoreSup.toSupplement()
        }
        
        let diets = firestoreDiets.compactMap { firestoreDiet in
            return firestoreDiet.toDiet()
        }
        
        // Convert Firebase doses to DoseRecords
        var doseRecords: [DoseRecord] = []
        
        // First, add all fetched doses from Firebase
        for firestoreDose in firestoreDoses {
            // Use the period from Firebase (it's already stored correctly)
            let doseRecord = DoseRecord(
                id: UUID(uuidString: firestoreDose.id) ?? UUID(),
                itemId: UUID(uuidString: firestoreDose.itemId) ?? UUID(),
                itemType: firestoreDose.itemType,
                scheduledTime: firestoreDose.scheduledTime,
                takenAt: firestoreDose.takenAt,
                isTaken: firestoreDose.isTaken,
                period: firestoreDose.period,  // Use the period from Firebase
                notes: firestoreDose.takenByName,
                firebaseDoseId: firestoreDose.id  // Preserve the original Firebase document ID
            )
            doseRecords.append(doseRecord)
        }
        
        // Create doses for any medications that don't have doses yet
        let today = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: today)
        
        // Create doses ONLY if they don't exist in Firebase already
        for medication in medications {
            for period in medication.schedule.timePeriods {
                // Check if dose already exists for this item and period (case-insensitive)
                let existingDose = doseRecords.first { dose in
                    dose.itemId == medication.id && dose.period.lowercased() == period.rawValue.lowercased()
                }
                
                if existingDose == nil {
                        // Create scheduled time based on period
                        let scheduledHour: Int
                        switch period {
                        case .breakfast: scheduledHour = 8
                        case .lunch: scheduledHour = 13
                        case .dinner: scheduledHour = 18
                        default: scheduledHour = 8
                        }
                        
                        let scheduledTime = calendar.date(byAdding: .hour, value: scheduledHour, to: startOfDay) ?? today
                        
                        // Create dose in Firebase ONLY once
                        // Use the period in the dose ID to prevent duplicates
                        let doseId = "\(medication.id.uuidString)_\(calendar.dateComponents([.year, .month, .day], from: today).year ?? 0)\(calendar.dateComponents([.year, .month, .day], from: today).month ?? 0)\(calendar.dateComponents([.year, .month, .day], from: today).day ?? 0)_\(period.rawValue)"
                        
                        let dose = DoseRecord(
                            id: UUID(uuidString: doseId) ?? UUID(),
                            itemId: medication.id,
                            itemType: "medication",
                            scheduledTime: scheduledTime,
                            takenAt: nil,
                            isTaken: false,
                            period: period.rawValue,
                            notes: nil,
                            firebaseDoseId: doseId  // Use the same ID for Firebase
                        )
                        doseRecords.append(dose)
                        
                        // Create in Firebase immediately (await to ensure it's created)
                        do {
                            try await FirebaseGroupDataService.shared.saveOrUpdateDose(
                                itemId: medication.id.uuidString,
                                itemName: medication.name,
                                itemType: "medication",
                                period: period.rawValue,
                                itemDosage: medication.dosage,
                                scheduledTime: scheduledTime,
                                isTaken: false
                            )
                            print("✅ Created dose in Firebase for \(medication.name) - \(period.rawValue)")
                        } catch {
                            print("⚠️ Failed to create dose in Firebase: \(error)")
                        }
                }
            }
        }
        
        for supplement in supplements {
            for period in supplement.schedule.timePeriods {
                let existingDose = doseRecords.first { dose in
                    dose.itemId == supplement.id && dose.period.lowercased() == period.rawValue.lowercased()
                }
                
                if existingDose == nil {
                        let scheduledHour: Int
                        switch period {
                        case .breakfast: scheduledHour = 8
                        case .lunch: scheduledHour = 13
                        case .dinner: scheduledHour = 18
                        default: scheduledHour = 8
                        }
                        
                        let scheduledTime = calendar.date(byAdding: .hour, value: scheduledHour, to: startOfDay) ?? today
                        
                        // Use the period in the dose ID to prevent duplicates
                        let doseId = "\(supplement.id.uuidString)_\(calendar.dateComponents([.year, .month, .day], from: today).year ?? 0)\(calendar.dateComponents([.year, .month, .day], from: today).month ?? 0)\(calendar.dateComponents([.year, .month, .day], from: today).day ?? 0)_\(period.rawValue)"
                        
                        let dose = DoseRecord(
                            id: UUID(uuidString: doseId) ?? UUID(),
                            itemId: supplement.id,
                            itemType: "supplement",
                            scheduledTime: scheduledTime,
                            takenAt: nil,
                            isTaken: false,
                            period: period.rawValue,
                            notes: nil,
                            firebaseDoseId: doseId  // Use the same ID for Firebase
                        )
                        doseRecords.append(dose)
                        
                        // Create in Firebase immediately (await to ensure it's created)
                        do {
                            try await FirebaseGroupDataService.shared.saveOrUpdateDose(
                                itemId: supplement.id.uuidString,
                                itemName: supplement.name,
                                itemType: "supplement",
                                period: period.rawValue,
                                itemDosage: supplement.dosage,
                                scheduledTime: scheduledTime,
                                isTaken: false
                            )
                            print("✅ Created dose in Firebase for \(supplement.name) - \(period.rawValue)")
                        } catch {
                            print("⚠️ Failed to create dose in Firebase: \(error)")
                        }
                }
            }
        }
        
        for diet in diets {
            for period in diet.schedule.timePeriods {
                let existingDose = doseRecords.first { dose in
                    dose.itemId == diet.id && dose.period.lowercased() == period.rawValue.lowercased()
                }
                
                if existingDose == nil {
                    // Create scheduled time based on period
                    let scheduledHour: Int
                    switch period {
                    case .breakfast: scheduledHour = 8
                    case .lunch: scheduledHour = 13
                    case .dinner: scheduledHour = 18
                    default: scheduledHour = 8
                    }
                    
                    let scheduledTime = calendar.date(byAdding: .hour, value: scheduledHour, to: startOfDay) ?? today
                    
                    // Use the period in the dose ID to prevent duplicates
                    let doseId = "\(diet.id.uuidString)_\(calendar.dateComponents([.year, .month, .day], from: today).year ?? 0)\(calendar.dateComponents([.year, .month, .day], from: today).month ?? 0)\(calendar.dateComponents([.year, .month, .day], from: today).day ?? 0)_\(period.rawValue)"
                    
                    let dose = DoseRecord(
                        id: UUID(uuidString: doseId) ?? UUID(),
                        itemId: diet.id,
                        itemType: "diet",
                        scheduledTime: scheduledTime,
                        takenAt: nil,
                        isTaken: false,
                        period: period.rawValue,
                        notes: nil,
                        firebaseDoseId: doseId  // Use the same ID for Firebase
                    )
                    doseRecords.append(dose)
                    
                    // Create in Firebase immediately (await to ensure it's created)
                    do {
                        try await FirebaseGroupDataService.shared.saveOrUpdateDose(
                            itemId: diet.id.uuidString,
                            itemName: diet.name,
                            itemType: "diet",
                            period: period.rawValue,
                            itemDosage: nil,  // Diet items don't have dosage
                            scheduledTime: scheduledTime,
                            isTaken: false
                        )
                        print("✅ Created dose in Firebase for \(diet.name) - \(period.rawValue)")
                    } catch {
                        print("⚠️ Failed to create dose in Firebase: \(error)")
                    }
                }
            }
        }
        
        AppLogger.main.info("📊 Fetched from Firebase: \(medications.count) meds, \(supplements.count) sups, \(diets.count) diets")
        
        return (medications, supplements, diets, doseRecords)
    }
}

