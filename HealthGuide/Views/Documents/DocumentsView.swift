//
//  DocumentsView.swift
//  HealthGuide
//
//  Medical documents storage and management
//  Elder-friendly interface with drag & drop support
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import PhotosUI

@available(iOS 18.0, *)
struct DocumentsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var accessManager = AccessSessionManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DocumentCategoryEntity.name, ascending: true)],
        animation: .default)
    private var categories: FetchedResults<DocumentCategoryEntity>
    
    @State private var selectedCategory: DocumentCategoryEntity?
    @State private var searchText = ""
    @State private var showAddCategory = false
    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var selectedDocument: DocumentEntity?
    @State private var selectedCategoryForViewing: DocumentCategoryEntity?
    @State private var showStorageAlert = false
    @State private var storageAlertMessage = ""
    @State private var showSaveDocument = false
    @State private var pendingFileToSave: (url: URL, fileSize: Int64)?
    @State private var capturedImageToSave: UIImage?
    @State private var showUpgradeAlert = false
    @State private var hasLoadedCategories = false
    
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
                
                VStack(spacing: 0) {
                    // Storage meter
                    storageMeter
                        .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        .padding(.vertical, AppTheme.Spacing.small)
                    
                    // Main content
                    if categories.isEmpty && searchText.isEmpty {
                        emptyStateView
                    } else {
                        categoryGridView
                    }
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search by filename or category")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { 
                            if subscriptionManager.subscriptionState.isActive || subscriptionManager.subscriptionState.isInTrial {
                                showFilePicker = true 
                            } else {
                                // Track document view for basic users
                                accessManager.trackDocumentView()
                                showUpgradeAlert = true
                            }
                        }) {
                            Label("Choose File", systemImage: "doc.badge.plus")
                        }
                        
                        Button(action: { 
                            if subscriptionManager.subscriptionState.isActive || subscriptionManager.subscriptionState.isInTrial {
                                showCamera = true 
                            } else {
                                // Track document view for basic users
                                accessManager.trackDocumentView()
                                showUpgradeAlert = true
                            }
                        }) {
                            Label("Take Photo", systemImage: "camera.fill")
                        }
                        
                        Divider()
                        
                        Button(action: { showAddCategory = true }) {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: AppTheme.ElderTypography.headline))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .frame(
                                minWidth: AppTheme.Dimensions.minimumTouchTarget,
                                minHeight: AppTheme.Dimensions.minimumTouchTarget
                            )
                    }
                }
            }
            .sheet(isPresented: $showAddCategory) {
                AddCategoryView()
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(
                    isPresented: $showFilePicker,
                    onDocumentPicked: { url, fileSize in
                        // Check total storage
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
                        // Check total storage
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
            .alert("Premium Feature", isPresented: $showUpgradeAlert) {
                Button("Upgrade", role: .none) {
                    // Navigate to subscription view
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        let subscriptionView = SubscriptionView()
                        let hostingController = UIHostingController(rootView: subscriptionView)
                        rootViewController.present(hostingController, animated: true)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Document upload and download is a premium feature. Basic users can view existing documents but cannot add new ones.")
            }
            .fullScreenCover(item: $selectedCategoryForViewing) { category in
                CategoryDocumentsView(category: category)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showSaveDocument) {
                if let pending = pendingFileToSave {
                    SaveDocumentSheet(
                        fileURL: pending.url,
                        fileSize: pending.fileSize,
                        preselectedCategory: selectedCategory,
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
                        preselectedCategory: selectedCategory,
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
        .onAppear {
            // Only create default categories once
            guard !hasLoadedCategories else {
                // Silently skip - no need to log
                return
            }
            
            print("🔍 DEBUG: DocumentsView appearing for first time")
            print("🔍 DEBUG: Categories count: \(categories.count)")
            
            createDefaultCategoriesIfNeeded()
            hasLoadedCategories = true
            
            print("🔍 DEBUG: After createDefaultCategoriesIfNeeded - created default categories")
        }
        // Add pull-to-refresh for manual updates
        .refreshable {
            // Trigger Core Data refresh by changing the fetch request
            // This will automatically reload the documents and categories
        }
        // Add debounced selective listening for document changes
        // Only responds to document-specific changes, not all Core Data saves
        .onReceive(
            NotificationCenter.default.publisher(for: .documentDataDidChange)
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        ) { _ in
            // FetchRequest will automatically update when Core Data changes
            // This is here for future use if we need manual refresh logic
        }
    }
    
    // MARK: - Storage Meter
    private var storageMeter: some View {
        VStack(spacing: AppTheme.Spacing.xSmall) {
            HStack {
                Text("Storage Used")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                Spacer()
                
                Text(storageUsageText)
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(storageColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.Colors.borderLight)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(storageColor)
                        .frame(width: geometry.size.width * storagePercentage, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
    
    // MARK: - Category Grid View
    private var categoryGridView: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.medium) {
                ForEach(Array(filteredCategories.enumerated()), id: \.element) { index, category in
                    CategoryListRow(
                        number: index + 1,
                        category: category,
                        onTap: {
                            selectedCategoryForViewing = category
                        }
                    )
                }
            }
            .padding(AppTheme.Spacing.screenPadding)
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.primaryBlue.opacity(0.6))
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Text("No Documents Yet")
                    .font(.monaco(AppTheme.ElderTypography.title))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("Store your medical records, lab results,\nand insurance cards for easy access")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Button(action: { 
                    if subscriptionManager.subscriptionState.isActive || subscriptionManager.subscriptionState.isInTrial {
                        showFilePicker = true 
                    } else {
                        accessManager.trackDocumentView()
                        showUpgradeAlert = true
                    }
                }) {
                    Label("Add Document", systemImage: "doc.badge.plus")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(AppTheme.Colors.primaryBlue)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
                
                Button(action: { 
                    if subscriptionManager.subscriptionState.isActive || subscriptionManager.subscriptionState.isInTrial {
                        showCamera = true 
                    } else {
                        accessManager.trackDocumentView()
                        showUpgradeAlert = true
                    }
                }) {
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
    
    // MARK: - Computed Properties
    private var storageUsed: Int64 {
        DocumentEntity.totalStorageUsed(in: viewContext)
    }
    
    private var storagePercentage: Double {
        min(DocumentEntity.storageUsagePercentage(in: viewContext) / 100.0, 1.0)
    }
    
    private var storageUsageText: String {
        let used = DocumentEntity.formatFileSize(storageUsed)
        let total = DocumentEntity.formatFileSize(DocumentEntity.maxTotalStorage)
        return "\(used) of \(total)"
    }
    
    private var storageColor: Color {
        if storagePercentage > 0.9 {
            return AppTheme.Colors.errorRed
        } else if storagePercentage > 0.7 {
            return AppTheme.Colors.warningOrange
        } else {
            return AppTheme.Colors.successGreen
        }
    }
    
    private var filteredCategories: [DocumentCategoryEntity] {
        if searchText.isEmpty {
            return Array(categories)
        } else {
            return categories.filter { category in
                category.displayName.localizedCaseInsensitiveContains(searchText) ||
                (category.documents as? Set<DocumentEntity>)?.contains { document in
                    document.matches(searchTerm: searchText)
                } ?? false
            }
        }
    }
    
    // MARK: - Methods
    private func createDefaultCategoriesIfNeeded() {
        DocumentCategoryEntity.createDefaultCategoriesIfNeeded(in: viewContext)
    }
    
    @MainActor
    private func saveDocument(
        from url: URL,
        filename: String,
        category: DocumentCategoryEntity,
        fileSize: Int64,
        notes: String?
    ) async {
        // Start accessing security-scoped resource again
        guard url.startAccessingSecurityScopedResource() else {
            storageAlertMessage = "Unable to access the file."
            showStorageAlert = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
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
            
            // Clear pending file
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
            // Compress image to JPEG
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                storageAlertMessage = "Failed to process image"
                showStorageAlert = true
                return
            }
            
            let fileSize = Int64(imageData.count)
            
            // Generate unique filename for storage
            let storageFilename = "\(UUID().uuidString).jpg"
            let destinationURL = DocumentEntity.medicalDocumentsDirectory.appendingPathComponent(storageFilename)
            
            // Save image to documents directory
            try imageData.write(to: destinationURL)
            
            // Create document entity
            let document = DocumentEntity(context: viewContext)
            document.filename = filename
            document.category = category.name
            document.categoryRelation = category
            document.fileType = "jpg"
            document.fileSize = fileSize
            document.localPath = storageFilename
            document.notes = notes
            
            // Update category document count
            category.updateDocumentCount()
            
            try viewContext.save()
            
            // Clear captured image
            capturedImageToSave = nil
            showSaveDocument = false
            
        } catch {
            storageAlertMessage = "Failed to save photo: \(error.localizedDescription)"
            showStorageAlert = true
        }
    }
}

// MARK: - Category List Row View
@available(iOS 18.0, *)
struct CategoryListRow: View {
    let number: Int
    let category: DocumentCategoryEntity
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.large) {
                // Icon where number used to be
                Image(systemName: category.safeIconName)
                    .font(.system(size: 32))
                    .foregroundColor(category.categoryColor)
                    .frame(width: 36)
                
                // Category name and details
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text(category.displayName)
                        .font(.monaco(AppTheme.ElderTypography.headline - 3))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: AppTheme.Spacing.medium) {
                        // Document count
                        HStack(spacing: AppTheme.Spacing.xSmall) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
                            Text("\(category.documentCount)")
                                .font(.monaco(AppTheme.ElderTypography.caption - 3))
                        }
                        
                        // Size
                        Text(category.formattedTotalSize)
                            .font(.monaco(AppTheme.ElderTypography.caption - 3))
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, AppTheme.Spacing.large)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(Color.white)
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#Preview {
    DocumentsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}