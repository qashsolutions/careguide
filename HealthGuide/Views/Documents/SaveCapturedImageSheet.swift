//
//  SaveCapturedImageSheet.swift
//  HealthGuide
//
//  Sheet for saving captured photos with metadata
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct SaveCapturedImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let image: UIImage
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
                        // Image preview
                        imagePreview
                        
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
            .navigationTitle("Save Photo")
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
                    .fontWeight(.bold)
                    .foregroundColor(canSave ? .blue : Color.gray)
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
    
    private var imagePreview: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 300)
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 8)
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
        filename = "\(category.displayName)_\(nextNumber)_\(timestamp)"
    }
}