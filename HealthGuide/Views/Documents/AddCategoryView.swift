//
//  AddCategoryView.swift
//  HealthGuide
//
//  Create new document categories/folders
//  Elder-friendly interface with icon selection
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct AddCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var categoryName = ""
    @State private var selectedIcon = DocumentCategoryEntity.DefaultIcons.general
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @FocusState private var isNameFieldFocused: Bool
    
    private let availableIcons = [
        DocumentCategoryEntity.DefaultIcons.general,
        DocumentCategoryEntity.DefaultIcons.labResults,
        DocumentCategoryEntity.DefaultIcons.prescriptions,
        DocumentCategoryEntity.DefaultIcons.insurance,
        DocumentCategoryEntity.DefaultIcons.immunization,
        DocumentCategoryEntity.DefaultIcons.imaging,
        DocumentCategoryEntity.DefaultIcons.emergency,
        DocumentCategoryEntity.DefaultIcons.dental,
        DocumentCategoryEntity.DefaultIcons.vision,
        DocumentCategoryEntity.DefaultIcons.other
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warm off-white gradient background
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
                    VStack(spacing: AppTheme.Spacing.xxLarge) {
                        // Preview
                        categoryPreview
                            .padding(.top, AppTheme.Spacing.xxLarge)
                        
                        // Name field
                        nameSection
                        
                        // Icon selection
                        iconSection
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCategory()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
    }
    
    // MARK: - Category Preview
    private var categoryPreview: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primaryBlue.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: selectedIcon)
                    .font(.system(size: 50))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
            }
            
            // Name
            Text(categoryName.isEmpty ? "Folder Name" : categoryName)
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(categoryName.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
        }
    }
    
    // MARK: - Name Section
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Folder Name")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            TextField("e.g., Lab Results, Insurance", text: $categoryName)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isNameFieldFocused)
                .autocorrectionDisabled()
        }
    }
    
    // MARK: - Icon Section
    private var iconSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Choose Icon")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: AppTheme.Spacing.medium
            ) {
                ForEach(availableIcons, id: \.self) { icon in
                    IconButton(
                        icon: icon,
                        isSelected: selectedIcon == icon,
                        action: { selectedIcon = icon }
                    )
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var canSave: Bool {
        !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Methods
    private func saveCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for duplicate
        let request = DocumentCategoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", trimmedName)
        
        do {
            let existingCategories = try viewContext.fetch(request)
            if !existingCategories.isEmpty {
                errorMessage = "A folder with this name already exists."
                showErrorAlert = true
                return
            }
            
            // Create new category
            let newCategory = DocumentCategoryEntity(context: viewContext)
            newCategory.name = trimmedName
            newCategory.iconName = selectedIcon
            
            try viewContext.save()
            dismiss()
            
        } catch {
            errorMessage = "Failed to create folder. Please try again."
            showErrorAlert = true
        }
    }
}

// MARK: - Icon Button
@available(iOS 18.0, *)
struct IconButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(isSelected ? .white : AppTheme.Colors.primaryBlue)
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                        .fill(isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.primaryBlue.opacity(0.1))
                )
        }
    }
}

// MARK: - Preview
#Preview {
    AddCategoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}