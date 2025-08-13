//
//  CategoryDocumentsView.swift
//  HealthGuide
//
//  View showing all documents in a specific category
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct CategoryDocumentsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let category: DocumentCategoryEntity
    
    @State private var searchText = ""
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var selectedDocument: DocumentEntity?
    @State private var showStorageAlert = false
    @State private var storageAlertMessage = ""
    @State private var showSaveDocument = false
    @State private var pendingFileToSave: (url: URL, fileSize: Int64)?
    @State private var capturedImageToSave: UIImage?
    
    @FetchRequest private var documents: FetchedResults<DocumentEntity>
    
    init(category: DocumentCategoryEntity) {
        self.category = category
        self._documents = FetchRequest<DocumentEntity>(
            sortDescriptors: [NSSortDescriptor(keyPath: \DocumentEntity.createdAt, ascending: false)],
            predicate: NSPredicate(format: "categoryRelation == %@", category),
            animation: .default
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "F8F8F8").ignoresSafeArea()
                
                if documents.isEmpty && searchText.isEmpty {
                    emptyStateView
                } else {
                    documentsList
                }
            }
            .navigationTitle(category.displayName)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search documents")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showFilePicker = true }) {
                            Label("Choose File", systemImage: "doc.badge.plus")
                        }
                        
                        Button(action: { showCamera = true }) {
                            Label("Take Photo", systemImage: "camera.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: AppTheme.ElderTypography.headline))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(
                    isPresented: $showFilePicker,
                    onDocumentPicked: { url, fileSize in
                        if !DocumentEntity.canAddFile(size: fileSize, in: viewContext) {
                            storageAlertMessage = "Adding this file would exceed the 15 MB storage limit."
                            showStorageAlert = true
                        } else {
                            pendingFileToSave = (url, fileSize)
                            showSaveDocument = true
                        }
                    },
                    onError: { message in
                        storageAlertMessage = message
                        showStorageAlert = true
                    }
                )
            }
            .fullScreenCover(isPresented: $showCamera) {
                SimpleCameraView(
                    isPresented: $showCamera,
                    onImageCaptured: { image, fileSize in
                        if !DocumentEntity.canAddFile(size: fileSize, in: viewContext) {
                            storageAlertMessage = "Adding this photo would exceed the 15 MB storage limit."
                            showStorageAlert = true
                        } else {
                            capturedImageToSave = image
                            showSaveDocument = true
                        }
                    },
                    onError: { message in
                        storageAlertMessage = message
                        showStorageAlert = true
                    }
                )
            }
            .sheet(item: $selectedDocument) { document in
                DocumentDetailView(document: document)
                    .environment(\.managedObjectContext, viewContext)
            }
            .alert("Storage Limit", isPresented: $showStorageAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(storageAlertMessage)
            }
            .sheet(isPresented: $showSaveDocument) {
                if let pending = pendingFileToSave {
                    SaveDocumentSheet(
                        fileURL: pending.url,
                        fileSize: pending.fileSize,
                        preselectedCategory: category,
                        onSave: { filename, category, notes in
                            Task {
                                await saveDocument(
                                    from: pending.url,
                                    filename: filename,
                                    category: category,
                                    fileSize: pending.fileSize,
                                    notes: notes
                                )
                            }
                        },
                        onCancel: {
                            pendingFileToSave = nil
                            showSaveDocument = false
                        }
                    )
                    .environment(\.managedObjectContext, viewContext)
                } else if let image = capturedImageToSave {
                    SaveCapturedImageSheet(
                        image: image,
                        preselectedCategory: category,
                        onSave: { filename, category, notes in
                            Task {
                                await saveImageDocument(
                                    image: image,
                                    filename: filename,
                                    category: category,
                                    notes: notes
                                )
                            }
                        },
                        onCancel: {
                            capturedImageToSave = nil
                            showSaveDocument = false
                        }
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
        }
    }
    
    private var documentsList: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.small) {
                // Category header
                categoryHeader
                
                // Documents
                ForEach(filteredDocuments) { document in
                    DocumentRowView(document: document) {
                        selectedDocument = document
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteDocument(document)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.screenPadding)
        }
    }
    
    private var categoryHeader: some View {
        HStack {
            Image(systemName: category.safeIconName)
                .font(.system(size: 36))
                .foregroundColor(category.categoryColor)
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                Text("\(documents.count) document\(documents.count == 1 ? "" : "s")")
                    .font(.monaco(AppTheme.ElderTypography.headline - 4))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(category.formattedTotalSize)
                    .font(.monaco(AppTheme.ElderTypography.caption - 3))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: category.safeIconName)
                .font(.system(size: 80))
                .foregroundColor(category.categoryColor.opacity(0.6))
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Text("No \(category.displayName) Documents")
                    .font(.monaco(AppTheme.ElderTypography.title))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("Add your first document to this folder")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Button(action: { showFilePicker = true }) {
                    Label("Add Document", systemImage: "doc.badge.plus")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(AppTheme.Colors.primaryBlue)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
                
                Button(action: { showCamera = true }) {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(AppTheme.Colors.successGreen)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Spacer()
        }
    }
    
    private var filteredDocuments: [DocumentEntity] {
        if searchText.isEmpty {
            return Array(documents)
        } else {
            return documents.filter { $0.matches(searchTerm: searchText) }
        }
    }
    
    private func deleteDocument(_ document: DocumentEntity) {
        // Delete the physical file
        if let localPath = document.localPath {
            let fileURL = DocumentEntity.medicalDocumentsDirectory.appendingPathComponent(localPath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Update category count before deletion
        if let category = document.categoryRelation {
            category.documentCount = max(0, category.documentCount - 1)
        }
        
        // Delete from Core Data
        viewContext.delete(document)
        
        do {
            try viewContext.save()
        } catch {
            print("Failed to delete document: \(error)")
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
        guard url.startAccessingSecurityScopedResource() else {
            storageAlertMessage = "Unable to access the file."
            showStorageAlert = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let fileExtension = url.pathExtension.lowercased()
            let storageFilename = "\(UUID().uuidString).\(fileExtension)"
            let destinationURL = DocumentEntity.medicalDocumentsDirectory.appendingPathComponent(storageFilename)
            
            try FileManager.default.copyItem(at: url, to: destinationURL)
            
            let document = DocumentEntity(context: viewContext)
            document.filename = filename
            document.category = category.name
            document.categoryRelation = category
            document.fileType = fileExtension
            document.fileSize = fileSize
            document.localPath = storageFilename
            document.notes = notes
            
            category.updateDocumentCount()
            
            try viewContext.save()
            
            pendingFileToSave = nil
            showSaveDocument = false
            
        } catch {
            storageAlertMessage = "Failed to save document: \(error.localizedDescription)"
            showStorageAlert = true
        }
    }
    
    @MainActor
    private func saveImageDocument(
        image: UIImage,
        filename: String,
        category: DocumentCategoryEntity,
        notes: String?
    ) async {
        do {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                storageAlertMessage = "Failed to process image"
                showStorageAlert = true
                return
            }
            
            let fileSize = Int64(imageData.count)
            let storageFilename = "\(UUID().uuidString).jpg"
            let destinationURL = DocumentEntity.medicalDocumentsDirectory.appendingPathComponent(storageFilename)
            
            try imageData.write(to: destinationURL)
            
            let document = DocumentEntity(context: viewContext)
            document.filename = filename
            document.category = category.name
            document.categoryRelation = category
            document.fileType = "jpg"
            document.fileSize = fileSize
            document.localPath = storageFilename
            document.notes = notes
            
            category.updateDocumentCount()
            
            try viewContext.save()
            
            capturedImageToSave = nil
            showSaveDocument = false
            
        } catch {
            storageAlertMessage = "Failed to save photo: \(error.localizedDescription)"
            showStorageAlert = true
        }
    }
}

// MARK: - Document Row View
@available(iOS 18.0, *)
struct DocumentRowView: View {
    let document: DocumentEntity
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.medium) {
                // File type icon
                Image(systemName: document.fileTypeEnum?.iconName ?? "doc")
                    .font(.system(size: 28))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                    .frame(width: 40)
                
                // Document info
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text(document.displayName)
                        .font(.monaco(AppTheme.ElderTypography.headline - 4))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                    
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Text(document.formattedFileSize)
                            .font(.monaco(AppTheme.ElderTypography.caption - 3))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Text("•")
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Text(document.formattedCreatedDate)
                            .font(.monaco(AppTheme.ElderTypography.caption - 3))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    
                    if let notes = document.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.monaco(AppTheme.ElderTypography.footnote - 2))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(AppTheme.Spacing.medium)
            .background(Color.white)
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}