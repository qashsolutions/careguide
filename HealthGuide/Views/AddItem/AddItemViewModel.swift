//  AddItemViewModel.swift
//  HealthGuide/Views/AddItem/AddItemViewModel.swift//
//  Business logic for adding health items with validation and limits
//  Swift 6 compliant with proper async/await and MainActor isolation
import Foundation

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
            
            // Schedule notifications in background task
            // This prevents blocking the main thread and avoids dispatch assertions
            Task {
                await MedicationNotificationScheduler.shared.scheduleNotificationsForNewMedication(medication.id)
            }
            
        case .supplement:
            let supplement = Supplement(
                name: name,
                dosage: dosage,
                notes: notes.isEmpty ? nil : notes,
                schedule: schedule
            )
            try await coreDataManager.saveSupplement(supplement)
            
            // Schedule notifications in background task
            // This prevents blocking the main thread and avoids dispatch assertions
            Task {
                await MedicationNotificationScheduler.shared.scheduleNotificationsForNewSupplement(supplement.id)
            }
            
        case .diet:
            let diet = Diet(
                name: name,
                portion: dosage.isEmpty ? "1 serving" : dosage,
                notes: notes.isEmpty ? nil : notes,
                schedule: schedule
            )
            try await coreDataManager.saveDiet(diet)
        }
    }
}
