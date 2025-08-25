//
//  EditMedicationView.swift
//  HealthGuide
//
//  Edit view for modifying existing medications
//  Supports all medication properties with validation
//

import SwiftUI

@available(iOS 18.0, *)
struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var groupService = FirebaseGroupService.shared
    @StateObject private var groupDataService = FirebaseGroupDataService.shared
    
    let medication: Medication
    
    // Form state
    @State private var name: String = ""
    @State private var dosage: String = ""
    @State private var quantity: Int = 1
    @State private var unit: Medication.DosageUnit = .tablet
    @State private var notes: String = ""
    @State private var frequency: Schedule.Frequency = .once
    @State private var selectedPeriods: [TimePeriod] = []
    @State private var category: Medication.MedicationCategory? = nil
    @State private var prescribedBy: String = ""
    
    // UI state
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.large) {
                    // Basic Information
                    basicInfoSection
                    
                    // Dosage Information
                    dosageSection
                    
                    // Schedule Section
                    scheduleSection
                    
                    // Additional Information
                    additionalInfoSection
                    
                    // Save Button
                    saveButton
                }
                .padding(AppTheme.Spacing.screenPadding)
            }
            .background(AppTheme.Colors.backgroundSecondary)
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.monaco(AppTheme.Typography.body))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveMedication()
                        }
                    }
                    .font(.monaco(AppTheme.Typography.body))
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || isSaving)
                }
            }
        }
        .onAppear {
            loadMedicationData()
        }
        .onChange(of: name) { _, _ in checkForChanges() }
        .onChange(of: dosage) { _, _ in checkForChanges() }
        .onChange(of: quantity) { _, _ in checkForChanges() }
        .onChange(of: unit) { _, _ in checkForChanges() }
        .onChange(of: notes) { _, _ in checkForChanges() }
        .onChange(of: frequency) { _, _ in checkForChanges() }
        .onChange(of: selectedPeriods) { _, _ in checkForChanges() }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Sections
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Basic Information")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.medium) {
                // Medication Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Medication Name")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    TextField("Enter medication name", text: $name)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .padding(AppTheme.Spacing.medium)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                        )
                }
                
                // Category
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Menu {
                        ForEach(Medication.MedicationCategory.allCases, id: \.self) { cat in
                            Button(action: {
                                category = cat
                            }) {
                                Label(cat.rawValue, systemImage: cat.icon)
                            }
                        }
                    } label: {
                        HStack {
                            if let category = category {
                                Image(systemName: category.icon)
                                Text(category.rawValue)
                            } else {
                                Text("Select category")
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .padding(AppTheme.Spacing.medium)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
    
    private var dosageSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Dosage Information")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.medium) {
                // Dosage
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dosage Strength")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    TextField("e.g., 500mg", text: $dosage)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .padding(AppTheme.Spacing.medium)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                        )
                }
                
                // Quantity and Unit
                HStack(spacing: AppTheme.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quantity")
                            .font(.monaco(AppTheme.Typography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        HStack {
                            Button(action: {
                                if quantity > 1 {
                                    quantity -= 1
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(AppTheme.Colors.primaryBlue)
                            }
                            
                            Text("\(quantity)")
                                .font(.monaco(AppTheme.ElderTypography.title))
                                .fontWeight(.semibold)
                                .frame(minWidth: 50)
                            
                            Button(action: {
                                quantity += 1
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(AppTheme.Colors.primaryBlue)
                            }
                        }
                        .padding(AppTheme.Spacing.small)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unit")
                            .font(.monaco(AppTheme.Typography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Menu {
                            ForEach(Medication.DosageUnit.allCases, id: \.self) { u in
                                Button(u.displayString(for: quantity)) {
                                    unit = u
                                }
                            }
                        } label: {
                            HStack {
                                Text(unit.displayString(for: quantity))
                                    .font(.monaco(AppTheme.ElderTypography.body))
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            .padding(AppTheme.Spacing.medium)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                    .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Schedule")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            FrequencySelector(
                selectedFrequency: $frequency,
                selectedPeriods: $selectedPeriods,
                itemType: .medication
            )
        }
    }
    
    private var additionalInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Additional Information")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.medium) {
                // Prescribed By
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prescribed By (Optional)")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    TextField("Doctor's name", text: $prescribedBy)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .padding(AppTheme.Spacing.medium)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                        )
                }
                
                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (Optional)")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    TextField("e.g., Take with food", text: $notes, axis: .vertical)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .lineLimit(3...5)
                        .padding(AppTheme.Spacing.medium)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .stroke(AppTheme.Colors.borderLight, lineWidth: 1)
                        )
                }
            }
        }
    }
    
    private var saveButton: some View {
        Button(action: {
            Task {
                await saveMedication()
            }
        }) {
            HStack {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isSaving ? "Saving..." : "Save Changes")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Dimensions.elderButtonHeight)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
        .tint(AppTheme.Colors.successGreen)
        .disabled(!hasChanges || isSaving || name.isEmpty || dosage.isEmpty || selectedPeriods.isEmpty)
        .padding(.top, AppTheme.Spacing.large)
    }
    
    // MARK: - Helper Methods
    
    private func loadMedicationData() {
        name = medication.name
        dosage = medication.dosage
        quantity = medication.quantity
        unit = medication.unit
        notes = medication.notes ?? ""
        frequency = medication.schedule.frequency
        selectedPeriods = medication.schedule.timePeriods
        category = medication.category
        prescribedBy = medication.prescribedBy ?? ""
    }
    
    private func checkForChanges() {
        hasChanges = name != medication.name ||
                    dosage != medication.dosage ||
                    quantity != medication.quantity ||
                    unit != medication.unit ||
                    notes != (medication.notes ?? "") ||
                    frequency != medication.schedule.frequency ||
                    selectedPeriods != medication.schedule.timePeriods ||
                    category != medication.category ||
                    prescribedBy != (medication.prescribedBy ?? "")
    }
    
    
    private func saveMedication() async {
        isSaving = true
        errorMessage = ""
        
        // Create updated medication
        var updatedMedication = medication
        updatedMedication.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedMedication.dosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedMedication.quantity = quantity
        updatedMedication.unit = unit
        updatedMedication.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedMedication.schedule = Schedule(frequency: frequency, timePeriods: selectedPeriods)
        updatedMedication.category = category
        updatedMedication.prescribedBy = prescribedBy.isEmpty ? nil : prescribedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedMedication.updatedAt = Date()
        
        do {
            // Validate
            try updatedMedication.validate()
            
            // Update in Core Data first
            try await CoreDataManager.shared.updateMedication(updatedMedication)
            
            // Update in Firebase if in a group
            if FirebaseGroupService.shared.currentGroup != nil {
                try await groupDataService.updateMedication(updatedMedication)
            }
            
            // Update notifications
            await MedicationNotificationScheduler.shared.scheduleDailyNotifications()
            
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isSaving = false
            }
        }
    }
}

// MARK: - Preview
#Preview {
    EditMedicationView(medication: Medication.sampleMetformin)
        .environmentObject(FirebaseGroupService.shared)
        .environmentObject(FirebaseGroupDataService.shared)
}