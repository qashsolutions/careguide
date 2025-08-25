//  AddItemViewModel.swift
//  HealthGuide/Views/AddItem/AddItemViewModel.swift//
//  Business logic for adding health items with validation and limits
//  Swift 6 compliant with proper async/await and MainActor isolation
import Foundation
import SwiftUI

// MARK: - Add Item View Model
@available(iOS 18.0, *)
@MainActor
final class AddItemViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var itemType: HealthItemType = .medication
    @Published var name = ""
    @Published var dosage = ""
    @Published var notes = ""
    @Published var frequency: Schedule.Frequency = .once
    @Published var selectedPeriods: [TimePeriod] = [.breakfast]
    @Published var selectedDays: Set<Date> = []
    
    // MARK: - Error and State Properties
    @Published var nameError: String?
    @Published var dosageError: String?
    @Published var showLimitAlert = false
    @Published var isSaving = false
    @Published var errorMessage = ""
    @Published var showErrorAlert = false
    @Published var saveSuccessful = false
    
    // MARK: - Dependencies
    private let coreDataManager = CoreDataManager.shared
    @AppStorage("hasHealthItems") private var hasHealthItems = false
    
    // MARK: - Computed Properties
    var canAdd: Bool {
        !name.isEmpty &&
        (itemType == .diet || !dosage.isEmpty) &&
        selectedPeriods.count == frequency.count
    }
    
    var reminderCount: Int {
        selectedDays.count * frequency.count
    }
    
    // MARK: - Initialization
    init() {
        selectedDays = Set(Date.generateDatesForNext(Configuration.HealthLimits.scheduleDaysAhead))
    }
    
    // MARK: - Public Methods
    func saveItem() {
        guard canAdd else { return }
        
        Task {
            await performSave()
        }
    }
    
    // MARK: - Private Methods
    private func performSave() async {
        isSaving = true
        defer { isSaving = false }
        
        let schedule = createSchedule()
        
        do {
            try await saveHealthItem(with: schedule)
            // Success - signal view to dismiss
            await MainActor.run {
                saveSuccessful = true
                // Mark that we now have health items
                hasHealthItems = true
            }
        } catch AppError.medicationLimitExceeded, AppError.supplementLimitExceeded {
            showLimitAlert = true
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
    
    private func createSchedule() -> Schedule {
        Schedule(
            frequency: frequency,
            timePeriods: selectedPeriods,
            startDate: Date(),
            activeDays: selectedDays
        )
    }
    
    private func saveHealthItem(with schedule: Schedule) async throws {
        switch itemType {
        case .medication:
            let medication = Medication(
                name: name,
                dosage: dosage,
                notes: notes.isEmpty ? nil : notes,
                schedule: schedule
            )
            try await coreDataManager.saveMedication(medication)
            // Notifications will be scheduled lazily when user views dashboard
            
            // Sync to cloud if in a group
            await syncToCloudIfNeeded(medication: medication)
            
        case .supplement:
            let supplement = Supplement(
                name: name,
                dosage: dosage,
                notes: notes.isEmpty ? nil : notes,
                schedule: schedule
            )
            try await coreDataManager.saveSupplement(supplement)
            // Notifications will be scheduled lazily when user views dashboard
            
            // Sync to cloud if in a group
            await syncToCloudIfNeeded(supplement: supplement)
            
        case .diet:
            let diet = Diet(
                name: name,
                portion: dosage.isEmpty ? "1 serving" : dosage,
                notes: notes.isEmpty ? nil : notes,
                schedule: schedule
            )
            try await coreDataManager.saveDiet(diet)
            
            // Sync to cloud if in a group
            await syncToCloudIfNeeded(diet: diet)
        }
    }
    
    // MARK: - Cloud Sync
    private func syncToCloudIfNeeded(medication: Medication) async {
        print("\n🔥 syncToCloudIfNeeded called for medication: \(medication.name)")
        print("   Checking current group...")
        print("   Group: \(FirebaseGroupService.shared.currentGroup?.name ?? "NO GROUP")")
        print("   Group ID: \(FirebaseGroupService.shared.currentGroup?.id ?? "NO ID")")
        
        // Always sync to Firebase group space
        do {
            print("   Calling FirebaseGroupDataService.saveMedication...")
            try await FirebaseGroupDataService.shared.saveMedication(medication)
            print("✅ Medication synced to Firebase group: \(medication.name)")
            
            // Don't create doses here - HealthDataProcessor will handle it
            // This prevents duplicate dose creation
            
            // If in a group, reference will be added automatically
            if let group = FirebaseGroupService.shared.currentGroup {
                print("📤 Synced to group: \(group.name) (ID: \(group.id))")
            } else {
                print("⚠️ WARNING: No group active - sync may have failed!")
            }
        } catch {
            print("❌ Failed to sync medication to Firebase: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error details: \(error.localizedDescription)")
            
            // Show error to user
            await MainActor.run {
                self.errorMessage = "Failed to sync to cloud: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
            // Note: Local data is already saved, so the item exists locally
        }
    }
    
    // DEPRECATED: Dose creation moved to HealthDataProcessor to prevent duplicates
    private func createDosesForMedication(_ medication: Medication) async {
        // Function body commented out to prevent duplicate dose creation
        /*
        let calendar = Calendar.current
        let today = Date()
        
        // Generate dose times for today based on schedule
        let doseTimes = medication.schedule.generateDoseTimes(for: today)
        
        for doseTime in doseTimes {
            // Only create doses for future times
            if doseTime > today {
                // Determine period from time
                let hour = calendar.component(.hour, from: doseTime)
                let period: String
                if hour < 12 {
                    period = "breakfast"
                } else if hour < 17 {
                    period = "lunch"
                } else {
                    period = "dinner"
                }
                
                do {
                    try await FirebaseGroupDataService.shared.saveOrUpdateDose(
                        itemId: medication.id.uuidString,
                        itemName: medication.name,
                        itemType: "medication",
                        period: period,
                        itemDosage: medication.dosage,
                        scheduledTime: doseTime,
                        isTaken: false
                    )
                    print("✅ Created dose for \(medication.name) at \(doseTime)")
                } catch {
                    print("❌ Failed to create dose: \(error)")
                }
            }
        }
        */
    }
    
    private func syncToCloudIfNeeded(supplement: Supplement) async {
        print("\n🔥 syncToCloudIfNeeded called for supplement: \(supplement.name)")
        print("   Checking current group...")
        print("   Group: \(FirebaseGroupService.shared.currentGroup?.name ?? "NO GROUP")")
        print("   Group ID: \(FirebaseGroupService.shared.currentGroup?.id ?? "NO ID")")
        
        // Always sync to Firebase group space
        do {
            print("   Calling FirebaseGroupDataService.saveSupplement...")
            try await FirebaseGroupDataService.shared.saveSupplement(supplement)
            print("✅ Supplement synced to Firebase group: \(supplement.name)")
            
            // Don't create doses here - HealthDataProcessor will handle it
            // This prevents duplicate dose creation
            
            // If in a group, reference will be added automatically
            if let group = FirebaseGroupService.shared.currentGroup {
                print("📤 Synced to group: \(group.name) (ID: \(group.id))")
            } else {
                print("⚠️ WARNING: No group active - sync may have failed!")
            }
        } catch {
            print("❌ Failed to sync supplement to Firebase: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error details: \(error.localizedDescription)")
            
            // Show error to user
            await MainActor.run {
                self.errorMessage = "Failed to sync to cloud: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
            // Note: Local data is already saved, so the item exists locally
        }
    }
    
    // DEPRECATED: Dose creation moved to HealthDataProcessor to prevent duplicates
    private func createDosesForSupplement(_ supplement: Supplement) async {
        // Function body commented out to prevent duplicate dose creation
        /*
        let calendar = Calendar.current
        let today = Date()
        
        // Generate dose times for today based on schedule
        let doseTimes = supplement.schedule.generateDoseTimes(for: today)
        
        for doseTime in doseTimes {
            // Only create doses for future times
            if doseTime > today {
                // Determine period from time
                let hour = calendar.component(.hour, from: doseTime)
                let period: String
                if hour < 12 {
                    period = "breakfast"
                } else if hour < 17 {
                    period = "lunch"
                } else {
                    period = "dinner"
                }
                
                do {
                    try await FirebaseGroupDataService.shared.saveOrUpdateDose(
                        itemId: supplement.id.uuidString,
                        itemName: supplement.name,
                        itemType: "supplement",
                        period: period,
                        itemDosage: supplement.dosage,
                        scheduledTime: doseTime,
                        isTaken: false
                    )
                    print("✅ Created dose for \(supplement.name) at \(doseTime)")
                } catch {
                    print("❌ Failed to create dose: \(error)")
                }
            }
        }
        */
    }
    
    private func syncToCloudIfNeeded(diet: Diet) async {
        print("🔥 syncToCloudIfNeeded called for diet: \(diet.name)")
        
        // Always sync to personal Firebase space (no group required)
        do {
            try await FirebaseGroupDataService.shared.saveDiet(diet)
            print("✅ Diet synced to Firebase group: \(diet.name)")
            
            // If in a group, reference will be added automatically
            if let group = FirebaseGroupService.shared.currentGroup {
                print("📤 Also synced reference to group: \(group.name)")
            } else {
                print("ℹ️ No group active - data saved to personal space only")
            }
        } catch {
            print("❌ Failed to sync diet to Firebase: \(error)")
            print("   Error details: \(error.localizedDescription)")
            
            // Show error to user for limit violations
            if let appError = error as? AppError {
                await MainActor.run {
                    self.errorMessage = appError.localizedDescription
                    self.showErrorAlert = true
                }
            }
            // Note: Local data is already saved, so the item exists locally
        }
    }
}
