//
//  DocumentPicker.swift
//  HealthGuide
//
//  File picker for importing medical documents
//  Supports PDF, images with size validation
//

import SwiftUI
import UniformTypeIdentifiers
import CoreData

@available(iOS 18.0, *)
struct DocumentPicker: UIViewControllerRepresentable {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let category: DocumentCategoryEntity?
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            .pdf,
            .jpeg,
            .png,
            .heic
        ]
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            Task {
                await parent.handlePickedDocument(at: url)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
    
    @MainActor
    private func handlePickedDocument(at url: URL) async {
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            showError("Unable to access the selected file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            // Get file attributes
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            // Validate file size (3 MB limit)
            guard DocumentEntity.isFileSizeValid(fileSize) else {
                let sizeInMB = String(format: "%.1f", Double(fileSize) / (1024 * 1024))
                showError("File size (\(sizeInMB) MB) exceeds the 3 MB limit. Please choose a smaller file.")
                return
            }
            
            // Check total storage
            guard DocumentEntity.canAddFile(size: fileSize, in: viewContext) else {
                showError("Adding this file would exceed the 15 MB storage limit.")
                return
            }
            
            // Show save dialog
            await showSaveDialog(for: url, fileSize: fileSize)
            
        } catch {
            showError("Failed to process the selected file.")
        }
    }
    
    @MainActor
    private func showSaveDialog(for url: URL, fileSize: Int64) async {
        let saveView = SaveDocumentView(
            fileURL: url,
            fileSize: fileSize,
            preselectedCategory: category,
            onSave: { filename, selectedCategory, notes in
                Task {
                    await self.saveDocument(
                        from: url,
                        filename: filename,
                        category: selectedCategory,
                        fileSize: fileSize,
                        notes: notes
                    )
                }
            }
        )
        .environment(\.managedObjectContext, viewContext)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let hostingController = UIHostingController(rootView: saveView)
            window.rootViewController?.present(hostingController, animated: true)
        }
    }
    
    @MainActor
    private func saveDocument(
        from url: URL,
        filename: String,
        category: DocumentCategoryEntity,
        fileSize: Int64,
        notes: String?
    ) async {
        do {
            // Generate unique filename for storage
            let fileExtension = url.pathExtension.lowercased()
            let storageFilename = "\(UUID().uuidString).\(fileExtension)"
            let destinationURL = DocumentEntity.medicalDocumentsDirectory.appendingPathComponent(storageFilename)
            
            // Copy file to app's documents directory
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            // Create document entity
            let document = DocumentEntity(context: viewContext)
            document.filename = filename
            document.category = category.name
            document.categoryRelation = category
            document.fileType = fileExtension
            document.fileSize = fileSize
            document.localPath = storageFilename
            document.notes = notes
            
            // Update category document count
            category.updateDocumentCount()
            
            try viewContext.save()
            dismiss()
            
        } catch {
            showError("Failed to save document.")
        }
    }
    
    private func showError(_ message: String) {
        // Show error alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.dismiss()
            })
            window.rootViewController?.present(alert, animated: true)
        }
    }
}

// MARK: - Save Document View
@available(iOS 18.0, *)
struct SaveDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let fileURL: URL
    let fileSize: Int64
    let preselectedCategory: DocumentCategoryEntity?
    let onSave: (String, DocumentCategoryEntity, String?) -> Void
    
    @State private var filename: String = ""
    @State private var selectedCategory: DocumentCategoryEntity?
    @State private var notes: String = ""
    
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
                filename = fileURL.deletingPathExtension().lastPathComponent
                selectedCategory = preselectedCategory ?? categories.first
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
            Text("Document Name")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            TextField("Enter document name", text: $filename)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Select Folder")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(categories) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
            }
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
}

// MARK: - Category Chip
@available(iOS 18.0, *)
struct CategoryChip: View {
    let category: DocumentCategoryEntity
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                Image(systemName: category.safeIconName)
                    .font(.system(size: 16))
                
                Text(category.displayName)
                    .font(.monaco(AppTheme.ElderTypography.body))
            }
            .foregroundColor(isSelected ? .white : category.categoryColor)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                    .fill(isSelected ? category.categoryColor : category.categoryColor.opacity(0.1))
            )
        }
        .frame(height: AppTheme.Dimensions.elderButtonHeight)
    }
}