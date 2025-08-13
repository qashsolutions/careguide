//  HealthGuide/Services/Dashboard/HealthDataProcessor.swift
//  Business logic for processing and organizing health items for dashboard display
//  Swift 6 compliant with proper async/await and actor isolation
import Foundation

// MARK: - Health Data Processor
/// Service responsible for fetching, processing, and organizing health data for dashboard display
@available(iOS 18.0, *)
actor HealthDataProcessor {
    
    // MARK: - Dependencies
    private let coreDataManager = CoreDataManager.shared
    
    // MARK: - Data Processing Result
    struct ProcessedHealthData: Sendable {
        let items: [(item: any HealthItem, dose: ScheduledDose?)]
        let periodCounts: [TimePeriod: Int]
        let lastUpdated: Date
    }
    
    // MARK: - Public Methods
    
    /// Fetch and process all health items for today's dashboard display
    /// - Returns: Processed health data organized by time periods
    func processHealthDataForToday() async throws -> ProcessedHealthData {
        // Fetch all health items concurrently for better performance
        async let medications = coreDataManager.fetchMedications()
        async let supplements = coreDataManager.fetchSupplements()
        async let dietItems = coreDataManager.fetchDietItems()
        async let allDoseRecords = coreDataManager.fetchDosesForDate(Date())
        
        // Wait for all data to be fetched
        let (medicationList, supplementList, dietItemList, doseRecords) = try await (medications, supplements, dietItems, allDoseRecords)
        
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
    
    /// Mark a specific dose as taken and return updated data
    /// - Parameters:
    ///   - itemId: ID of the health item
    ///   - doseId: ID of the specific dose
    /// - Returns: Updated processed health data
    func markDoseTakenAndRefresh(itemId: UUID, doseId: UUID) async throws -> ProcessedHealthData {
        // First, determine the type of item to call the correct method
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
        
        // Return refreshed data to update UI
        return try await processHealthDataForToday()
    }
    
    // MARK: - Private Processing Methods
    
    /// Convert DoseRecord to ScheduledDose
    private func convertDoseRecordToScheduledDose(_ record: DoseRecord) -> ScheduledDose {
        guard let period = TimePeriod(rawValue: record.period) else {
            // Default to breakfast if period is invalid
            return ScheduledDose(
                id: record.id,
                time: record.scheduledTime,
                period: .breakfast,
                isTaken: record.isTaken,
                takenAt: record.takenAt
            )
        }
        
        return ScheduledDose(
            id: record.id,
            time: record.scheduledTime,
            period: period,
            isTaken: record.isTaken,
            takenAt: record.takenAt
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
}
