//
//  AddItemView.swift
//  HealthGuide/Views/AddItem/AddItemView.swift
//
//  Universal add screen for medications, supplements, and diet
//  Uses reusable components for consistent UI patterns
//

import SwiftUI

@available(iOS 18.0, *)
struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AddItemViewModel()
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, dosage, notes
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warm off-white gradient background for reduced eye strain
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "F8F8F8"),
                        Color(hex: "FAFAFA")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        ItemTypeSelector(selectedType: $viewModel.itemType)
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        
                        formContent
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        
                        scheduleSection
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        
                        addButton
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                            .padding(.bottom, AppTheme.Spacing.xxxLarge)
                    }
                    .padding(.top, AppTheme.Spacing.medium)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
            .alert(AppStrings.Validation.dailyLimitTitle, isPresented: $viewModel.showLimitAlert) {
                Button(AppStrings.Validation.viewTodayButton) { dismiss() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(AppStrings.Validation.dailyLimitMessage)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .onChange(of: viewModel.saveSuccessful) { _, success in
                if success {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Form Content
    
    private var formContent: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            nameField
            
            if viewModel.itemType != .diet {
                dosageField
            }
            
            notesField
        }
    }
    
    private var nameField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(nameLabel)
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            AppleIntelligenceField(
                text: $viewModel.name,
                placeholder: AppStrings.AddItem.namePlaceholder,
                itemType: viewModel.itemType,
                fieldType: .name
            )
            .focused($focusedField, equals: .name)
            .accessibilityIdentifier("medication_name_field")
            .accessibilityLabel(nameLabel)
            .accessibilityHint("Enter the name of your \(viewModel.itemType.rawValue)")
            
            if let error = viewModel.nameError {
                ValidationMessageView(message: error, type: .error)
            }
        }
    }
    
    private var dosageField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(AppStrings.AddItem.dosageLabel)
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            AppleIntelligenceField(
                text: $viewModel.dosage,
                placeholder: AppStrings.AddItem.dosagePlaceholder,
                itemType: viewModel.itemType,
                fieldType: .dosage
            )
            .focused($focusedField, equals: .dosage)
            .accessibilityIdentifier("dosage_field")
            .accessibilityLabel("Dosage amount")
            .accessibilityHint("Enter the dosage, for example 500mg")
            
            if let error = viewModel.dosageError {
                ValidationMessageView(message: error, type: .error)
            }
        }
    }
    
    private var notesField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text(AppStrings.AddItem.notesLabel)
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            TextField(AppStrings.AddItem.notesLabel, text: $viewModel.notes)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($focusedField, equals: .notes)
                .accessibilityIdentifier("notes_field")
                .accessibilityLabel("Optional notes")
                .accessibilityHint("Add any special instructions")
        }
    }
    
    // MARK: - Schedule Section
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            frequencySection
            scheduleDaysSection
            confirmationMessage
        }
    }
    
    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(AppStrings.AddItem.frequencyLabel)
                .font(.monaco(AppTheme.ElderTypography.headline))
                .fontWeight(AppTheme.Typography.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            FrequencySelector(
                selectedFrequency: $viewModel.frequency,
                selectedPeriods: $viewModel.selectedPeriods,
                itemType: viewModel.itemType
            )
        }
    }
    
    private var scheduleDaysSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(AppStrings.AddItem.scheduleLabel)
                .font(.monaco(AppTheme.ElderTypography.headline))
                .fontWeight(AppTheme.Typography.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            ScheduleSelector(selectedDays: $viewModel.selectedDays)
        }
    }
    
    @ViewBuilder
    private var confirmationMessage: some View {
        if viewModel.reminderCount > 0 {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.Colors.successGreen)
                
                Text(String(format: AppStrings.Schedule.confirmationFormat, viewModel.reminderCount, viewModel.selectedDays.count))
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(.top, AppTheme.Spacing.small)
        }
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button(action: viewModel.saveItem) {
            Text(viewModel.canAdd ? addButtonTitle : "Complete Required Fields")
                .font(.monaco(AppTheme.ElderTypography.callout))
                .fontWeight(AppTheme.Typography.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Dimensions.elderButtonHeight)
                .background(buttonBackground)
                .shadow(
                    color: viewModel.canAdd ? AppTheme.Colors.primaryBlue.opacity(AppTheme.Effects.buttonShadowOpacity) : .clear,
                    radius: AppTheme.Effects.buttonShadowRadius,
                    x: 0,
                    y: 4
                )
        }
        .disabled(!viewModel.canAdd || viewModel.isSaving)
        .overlay(
            viewModel.isSaving ? ProgressView().tint(.white) : nil
        )
        .accessibilityLabel(viewModel.canAdd ? "Add item" : "Complete required fields")
        .accessibilityHint(viewModel.canAdd ? "Saves the health item to your schedule" : "Fill in all required fields to enable")
    }
    
    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .fill(viewModel.canAdd ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary)
    }
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        switch viewModel.itemType {
        case .medication:
            return AppStrings.AddItem.title
        case .supplement:
            return AppStrings.AddItem.supplementTitle
        case .diet:
            return AppStrings.AddItem.dietTitle
        }
    }
    
    private var nameLabel: String {
        switch viewModel.itemType {
        case .medication:
            return AppStrings.AddItem.medicationNameLabel
        case .supplement:
            return AppStrings.AddItem.supplementNameLabel
        case .diet:
            return AppStrings.AddItem.dietNameLabel
        }
    }
    
    private var addButtonTitle: String {
        switch viewModel.itemType {
        case .medication:
            return AppStrings.AddItem.addMedicationButton
        default:
            return AppStrings.AddItem.addButton
        }
    }
}

// MARK: - Preview
#Preview {
    AddItemView()
}
