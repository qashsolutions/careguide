//
//  MedicationDetailView.swift
//  HealthGuide
//
//  Detail view for medications with edit and delete functionality
//  Designed for caregivers who need to manage multiple medications
//

import SwiftUI

@available(iOS 18.0, *)
struct MedicationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var groupService = FirebaseGroupService.shared
    @StateObject private var groupDataService = FirebaseGroupDataService.shared
    
    let medication: Medication
    @State private var showEditView = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showError = false
    
    // Check if user can edit
    private var canEdit: Bool {
        groupService.userHasWritePermission
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    // Medication Info Card
                    medicationInfoSection
                    
                    // Schedule Section
                    scheduleSection
                    
                    // Additional Details
                    if medication.notes != nil || medication.prescribedBy != nil {
                        additionalDetailsSection
                    }
                    
                    // Action Buttons (if user has permission)
                    if canEdit {
                        actionButtonsSection
                    }
                }
                .padding(AppTheme.Spacing.screenPadding)
            }
            .background(AppTheme.Colors.backgroundSecondary)
            .navigationTitle("Medication Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.monaco(AppTheme.Typography.body))
                }
            }
        }
        .sheet(isPresented: $showEditView) {
            EditMedicationView(medication: medication)
        }
        .alert("Delete Medication", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteMedication()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(medication.name)? This will also delete all scheduled doses.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteError ?? "An error occurred")
        }
    }
    
    // MARK: - Sections
    
    private var medicationInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            // Header with icon
            HStack {
                Image(systemName: medication.category?.icon ?? "pills.fill")
                    .font(.system(size: 30))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(medication.category?.rawValue ?? "Medication")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Dosage Info
            HStack {
                Label {
                    Text("Dosage")
                        .font(.monaco(AppTheme.Typography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } icon: {
                    Image(systemName: "pills.circle")
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                }
                
                Spacer()
                
                Text("\(medication.dosage) - \(medication.fullDosageDescription)")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .fill(Color.white)
                .shadow(radius: 2)
        )
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Schedule")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.small) {
                // Frequency
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .frame(width: 24)
                    
                    Text("Frequency")
                        .font(.monaco(AppTheme.Typography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text(medication.schedule.frequency.displayName)
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
                
                Divider()
                
                // Time Periods
                HStack(alignment: .top) {
                    Image(systemName: "clock")
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .frame(width: 24)
                    
                    Text("Times")
                        .font(.monaco(AppTheme.Typography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(medication.schedule.timePeriods, id: \.self) { period in
                            Text(period.displayName)
                                .font(.monaco(AppTheme.Typography.body))
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.Colors.textPrimary)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(Color.white)
                    .shadow(radius: 2)
            )
        }
    }
    
    private var additionalDetailsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Additional Information")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.small) {
                if let prescribedBy = medication.prescribedBy {
                    HStack {
                        Image(systemName: "person.badge.shield.checkmark")
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .frame(width: 24)
                        
                        Text("Prescribed by")
                            .font(.monaco(AppTheme.Typography.body))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Text(prescribedBy)
                            .font(.monaco(AppTheme.Typography.body))
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                    }
                    
                    if medication.notes != nil {
                        Divider()
                    }
                }
                
                if let notes = medication.notes, !notes.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "note.text")
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.monaco(AppTheme.Typography.body))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            
                            Text(notes)
                                .font(.monaco(AppTheme.Typography.body))
                                .foregroundColor(AppTheme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(Color.white)
                    .shadow(radius: 2)
            )
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Edit Button
            Button(action: {
                showEditView = true
            }) {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                    Text("Edit Medication")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Dimensions.elderButtonHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
            .tint(AppTheme.Colors.primaryBlue)
            
            // Delete Button
            Button(action: {
                showDeleteConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 20))
                    Text("Delete Medication")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Dimensions.elderButtonHeight)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
            .tint(AppTheme.Colors.warningOrange)
            .disabled(isDeleting)
            .overlay {
                if isDeleting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
        }
        .padding(.top, AppTheme.Spacing.large)
    }
    
    // MARK: - Actions
    
    private func deleteMedication() async {
        isDeleting = true
        deleteError = nil
        
        do {
            // Delete from Core Data first
            try await CoreDataManager.shared.deleteMedication(medication.id)
            
            // Delete from Firebase if in a group
            if FirebaseGroupService.shared.currentGroup != nil {
                try await groupDataService.deleteMedication(medication.id.uuidString)
            }
            
            // Dismiss view
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                deleteError = error.localizedDescription
                showError = true
                isDeleting = false
            }
        }
    }
}

// MARK: - Preview
#Preview {
    MedicationDetailView(medication: Medication.sampleMetformin)
        .environmentObject(FirebaseGroupService.shared)
        .environmentObject(FirebaseGroupDataService.shared)
}