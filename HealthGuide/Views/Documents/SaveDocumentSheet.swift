//
//  SaveDocumentSheet.swift
//  HealthGuide
//
//  Sheet for saving documents with metadata
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct SaveDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let fileURL: URL
    let fileSize: Int64
    let preselectedCategory: DocumentCategoryEntity?
    let onSave: (String, DocumentCategoryEntity, String?) -> Void
    let onCancel: () -> Void
    
    @State private var filename: String = ""
    @State private var selectedCategory: DocumentCategoryEntity?
    @State private var notes: String = ""
    @State private var useAutoFilename: Bool = true
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DocumentCategoryEntity.name, ascending: true)],
        animation: .default)
    private var categories: FetchedResults<DocumentCategoryEntity>
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "F8F8F8").ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        // File info
                        fileInfoSection
                        
                        // Filename field
                        filenameSection
                        
                        // Category selection
                        categorySection
                        
                        // Notes field
                        notesSection
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle("Save Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let category = selectedCategory {
                            onSave(filename, category, notes.isEmpty ? nil : notes)
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedCategory = preselectedCategory ?? categories.first
                generateAutoFilename()
            }
            .onChange(of: selectedCategory) {
                if useAutoFilename {
                    generateAutoFilename()
                }
            }
        }
    }
    
    private var fileInfoSection: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            HStack {
                Image(systemName: DocumentEntity.FileType.from(filename: fileURL.lastPathComponent)?.iconName ?? "doc")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileURL.lastPathComponent)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(DocumentEntity.formatFileSize(fileSize))
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
            }
            .padding(AppTheme.Spacing.medium)
            .background(Color.white)
            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
        }
    }
    
    private var filenameSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Document Name")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                Spacer()
                
                Toggle("Auto-name", isOn: $useAutoFilename)
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .onChange(of: useAutoFilename) {
                        if useAutoFilename {
                            generateAutoFilename()
                        }
                    }
            }
            
            TextField("Enter document name", text: $filename)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(useAutoFilename)
                .opacity(useAutoFilename ? 0.6 : 1.0)
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Select Folder")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            // Vertical list of folders with numbers
            VStack(spacing: AppTheme.Spacing.small) {
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    CategoryRow(
                        number: index + 1,
                        category: category,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(Color(hex: "F5F5F7"))
            )
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Notes (Optional)")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            TextField("Add notes about this document", text: $notes, axis: .vertical)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...5)
        }
    }
    
    private var canSave: Bool {
        !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedCategory != nil
    }
    
    private func generateAutoFilename() {
        guard let category = selectedCategory else { return }
        
        // Count existing documents in this category
        let categoryDocuments = (category.documents as? Set<DocumentEntity>) ?? []
        let nextNumber = categoryDocuments.count + 1
        
        // Generate timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        // Create filename: Category_Number_Timestamp
        let baseName = "\(category.displayName)_\(nextNumber)_\(timestamp)"
        
        filename = baseName
    }
}

// MARK: - Category Row View
@available(iOS 18.0, *)
struct CategoryRow: View {
    let number: Int
    let category: DocumentCategoryEntity
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.medium) {
                // Number badge
                Text("\(number)")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? category.categoryColor : AppTheme.Colors.textSecondary)
                    .frame(width: 32)
                
                // Folder name
                Text(category.displayName)
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Icon on the right
                Image(systemName: (category.iconName?.isEmpty == false ? category.iconName : nil) ?? "folder")
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? category.categoryColor : AppTheme.Colors.textSecondary.opacity(0.6))
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? category.categoryColor : AppTheme.Colors.textSecondary.opacity(0.3))
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(Color.white)
                    .shadow(
                        color: isSelected ? category.categoryColor.opacity(0.15) : Color.black.opacity(0.05),
                        radius: isSelected ? 8 : 4,
                        x: 0,
                        y: 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .stroke(
                        isSelected ? category.categoryColor.opacity(0.3) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2) // Small padding for shadow
    }
}