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
        
        // Wait for all data to be fetched
        let (medicationList, supplementList, dietItemList) = try await (medications, supplements, dietItems)
        
        #if DEBUG
        print("🏥 HealthDataProcessor: Fetched \(medicationList.count) medications, \(supplementList.count) supplements, \(dietItemList.count) diet items")
        #endif
        
        // Process each type of health item
        var allItems: [(item: any HealthItem, dose: ScheduledDose?)] = []
        
        // Process medications with their scheduled doses
        allItems.append(contentsOf: processHealthItems(medicationList))
        
        // Process supplements with their scheduled doses
        allItems.append(contentsOf: processHealthItems(supplementList))
        
        // Process diet items with their scheduled doses
        allItems.append(contentsOf: processHealthItems(dietItemList))
        
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
    
    /// Process a collection of health items to include their scheduled doses for today
    /// - Parameter items: Array of health items to process
    /// - Returns: Array of tuples containing items and their associated doses
    private func processHealthItems<T: HealthItem>(_ items: [T]) -> [(item: any HealthItem, dose: ScheduledDose?)] {
        var processedItems: [(item: any HealthItem, dose: ScheduledDose?)] = []
        
        for item in items {
            let todaysDoses = item.dosesForToday()
            
            if todaysDoses.isEmpty && item.isScheduledForToday() {
                // Item is scheduled but has no specific doses - add as general item
                processedItems.append((item: item, dose: nil))
            } else {
                // Item has specific scheduled doses - add each dose separately
                for dose in todaysDoses {
                    processedItems.append((item: item, dose: dose))
                }
            }
        }
        
        return processedItems
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
            .dinner: 0,
            .bedtime: 0
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
        
        switch hour {
        case 5..<11:
            return .breakfast
        case 11..<16:
            return .lunch
        case 16..<21:
            return .dinner
        default:
            return .bedtime
        }
    }
    
    /// Get all available time periods in display order
    /// - Returns: Array of time periods for UI display
    static func getAllTimePeriods() -> [TimePeriod] {
        return [.breakfast, .lunch, .dinner, .bedtime]
    }
}
