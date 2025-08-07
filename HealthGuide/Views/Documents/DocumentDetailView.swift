//
//  DocumentDetailView.swift
//  HealthGuide
//
//  View and share medical documents
//  Elder-friendly interface with large touch targets
//

import SwiftUI
import PDFKit
import QuickLook
import CoreData

@available(iOS 18.0, *)
struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let document: DocumentEntity
    
    @State private var showShareSheet = false
    @State private var showDeleteAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isEditingNotes = false
    @State private var editedNotes = ""
    
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
                
                if document.fileExists {
                    documentContent
                } else {
                    fileNotFoundView
                }
            }
            .navigationTitle(document.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = document.fileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Delete Document", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteDocument()
                }
            } message: {
                Text("Are you sure you want to delete \"\(document.displayName)\"? This action cannot be undone.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                editedNotes = document.notes ?? ""
            }
        }
    }
    
    // MARK: - Document Content
    private var documentContent: some View {
        VStack(spacing: 0) {
            // Document info header
            documentInfoHeader
            
            // Document viewer
            if let fileType = document.fileTypeEnum {
                switch fileType {
                case .pdf:
                    pdfViewer
                case .jpg, .jpeg, .png, .heic:
                    imageViewer
                }
            }
            
            // Notes section
            notesSection
        }
    }
    
    // MARK: - Document Info Header
    private var documentInfoHeader: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            HStack {
                // File type icon
                Image(systemName: document.fileTypeEnum?.iconName ?? "doc")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.displayName)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Text(document.formattedFileSize)
                            .font(.monaco(AppTheme.ElderTypography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Text("•")
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Text(document.formattedCreatedDate)
                            .font(.monaco(AppTheme.ElderTypography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(AppTheme.Spacing.medium)
            .background(Color.white)
        }
        .padding(.horizontal, AppTheme.Spacing.screenPadding)
        .padding(.vertical, AppTheme.Spacing.small)
    }
    
    // MARK: - PDF Viewer
    private var pdfViewer: some View {
        Group {
            if let url = document.fileURL {
                PDFViewWrapper(url: url)
                    .background(Color.white)
            } else {
                Text("Unable to load PDF")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Image Viewer
    private var imageViewer: some View {
        ScrollView {
            if let url = document.fileURL,
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(AppTheme.Spacing.screenPadding)
            } else {
                Text("Unable to load image")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(Color.white)
    }
    
    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Notes")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Button(action: { isEditingNotes.toggle() }) {
                    Text(isEditingNotes ? "Done" : "Edit")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
            
            if isEditingNotes {
                TextField("Add notes about this document", text: $editedNotes, axis: .vertical)
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...10)
                    .onChange(of: editedNotes) {
                        saveNotes()
                    }
            } else {
                Text(editedNotes.isEmpty ? "No notes added" : editedNotes)
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(editedNotes.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppTheme.Spacing.medium)
                    .background(Color.white)
                    .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
            }
        }
        .padding(AppTheme.Spacing.screenPadding)
    }
    
    // MARK: - File Not Found View
    private var fileNotFoundView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.warningOrange)
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Text("Document Not Found")
                    .font(.monaco(AppTheme.ElderTypography.title))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("The file may have been moved or deleted")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Button(action: { showDeleteAlert = true }) {
                Text("Remove from Library")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .foregroundColor(AppTheme.Colors.errorRed)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                            .stroke(AppTheme.Colors.errorRed, lineWidth: 2)
                    )
            }
        }
        .padding(AppTheme.Spacing.xxLarge)
    }
    
    // MARK: - Methods
    private func saveNotes() {
        document.notes = editedNotes.isEmpty ? nil : editedNotes
        
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Failed to save notes"
            showErrorAlert = true
        }
    }
    
    private func deleteDocument() {
        // Delete physical file
        document.deleteFile()
        
        // Update category count
        if let category = document.categoryRelation {
            category.updateDocumentCount()
        }
        
        // Delete entity
        viewContext.delete(document)
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to delete document"
            showErrorAlert = true
        }
    }
}

// MARK: - PDF View Wrapper
@available(iOS 18.0, *)
struct PDFViewWrapper: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Share Sheet
@available(iOS 18.0, *)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
#Preview {
    let context = PersistenceController.preview.container.viewContext
    let document = DocumentEntity(context: context)
    document.filename = "Lab Results.pdf"
    document.fileType = "pdf"
    document.fileSize = 1024 * 500 // 500 KB
    document.createdAt = Date()
    
    return DocumentDetailView(document: document)
        .environment(\.managedObjectContext, context)
}