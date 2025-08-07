//
//  CameraView.swift
//  HealthGuide
//
//  Camera interface for capturing medical documents
//  Production-ready with permissions handling and elder-friendly UX
//

import SwiftUI
import AVFoundation
import Photos
import CoreData

@available(iOS 18.0, *)
struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var camera = CameraModel()
    
    let category: DocumentCategoryEntity?
    
    @State private var showPermissionAlert = false
    @State private var showSaveView = false
    @State private var capturedImage: UIImage?
    @State private var showFlashOptions = false
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(camera: camera)
                .ignoresSafeArea()
            
            // Overlay controls
            VStack {
                // Top bar
                topBar
                
                Spacer()
                
                // Bottom controls
                bottomControls
            }
            
            // Permission denied view
            if camera.permissionDenied {
                permissionDeniedView
            }
        }
        .onAppear {
            camera.checkPermission()
        }
        .alert("Camera Access Required", isPresented: $showPermissionAlert) {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        } message: {
            Text("Please allow camera access in Settings to capture documents.")
        }
        .fullScreenCover(isPresented: $showSaveView) {
            if let image = capturedImage {
                SaveCapturedDocumentView(
                    image: image,
                    category: category,
                    onSave: { filename, selectedCategory, notes in
                        Task {
                            await saveImageDocument(
                                image: image,
                                filename: filename,
                                category: selectedCategory,
                                notes: notes
                            )
                        }
                    },
                    onRetake: {
                        capturedImage = nil
                        showSaveView = false
                        camera.retakePhoto()
                    }
                )
                .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            // Cancel button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding()
            
            Spacer()
            
            // Flash button
            Button(action: { camera.toggleFlash() }) {
                Image(systemName: camera.flashIcon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding()
        }
    }
    
    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Helper text
            Text("Position document within frame")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(.white)
                .padding(.horizontal, AppTheme.Spacing.large)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(Capsule().fill(Color.black.opacity(0.7)))
            
            // Capture button
            Button(action: capturePhoto) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 90, height: 90)
                }
            }
            .disabled(camera.isTakingPhoto)
            .padding(.bottom, AppTheme.Spacing.xxxLarge)
        }
    }
    
    // MARK: - Permission Denied View
    private var permissionDeniedView: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xxLarge) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.7))
                
                VStack(spacing: AppTheme.Spacing.medium) {
                    Text("Camera Access Required")
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .foregroundColor(.white)
                    
                    Text("To capture documents, please\nallow camera access in Settings")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }) {
                    Text("Open Settings")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(width: 200)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(Color.white)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
            }
        }
    }
    
    // MARK: - Methods
    private func capturePhoto() {
        camera.takePhoto { image in
            self.capturedImage = image
            self.showSaveView = true
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
                throw NSError(domain: "CameraView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])
            }
            
            let fileSize = Int64(imageData.count)
            
            // Validate file size
            guard DocumentEntity.isFileSizeValid(fileSize) else {
                throw NSError(domain: "CameraView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Image exceeds 2 MB limit"])
            }
            
            // Check total storage
            guard DocumentEntity.canAddFile(size: fileSize, in: viewContext) else {
                throw NSError(domain: "CameraView", code: 3, userInfo: [NSLocalizedDescriptionKey: "Storage limit exceeded"])
            }
            
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
            dismiss()
            
        } catch {
            // Show error alert
            print("Error saving document: \(error.localizedDescription)")
        }
    }
}

// MARK: - Camera Model
@available(iOS 18.0, *)
@MainActor
class CameraModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var permissionDenied = false
    @Published var isTakingPhoto = false
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    
    private var output = AVCapturePhotoOutput()
    private var photoCompletion: ((UIImage) -> Void)?
    
    var flashIcon: String {
        switch flashMode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUp()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        self.setUp()
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            break
        }
    }
    
    private func setUp() {
        do {
            session.beginConfiguration()
            
            // Add input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                return
            }
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Add output
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
            
            // Start session on background queue
            Task(priority: .background) {
                session.startRunning()
            }
        } catch {
            print("Camera setup error: \(error.localizedDescription)")
        }
    }
    
    func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        case .auto: flashMode = .off
        @unknown default: flashMode = .off
        }
    }
    
    func takePhoto(completion: @escaping (UIImage) -> Void) {
        guard !isTakingPhoto else { return }
        
        isTakingPhoto = true
        photoCompletion = completion
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func retakePhoto() {
        isTakingPhoto = false
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            Task { @MainActor in
                self.isTakingPhoto = false
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            Task { @MainActor in
                self.isTakingPhoto = false
            }
            return
        }
        
        Task { @MainActor in
            self.photoCompletion?(image)
            self.isTakingPhoto = false
        }
    }
}

// MARK: - Camera Preview View
@available(iOS 18.0, *)
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: camera.session)
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Save Captured Document View
@available(iOS 18.0, *)
struct SaveCapturedDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let image: UIImage
    let category: DocumentCategoryEntity?
    let onSave: (String, DocumentCategoryEntity, String?) -> Void
    let onRetake: () -> Void
    
    @State private var filename = "Scanned Document"
    @State private var selectedCategory: DocumentCategoryEntity?
    @State private var notes = ""
    
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
            .navigationTitle("Save Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retake") {
                        onRetake()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let category = selectedCategory {
                            onSave(filename, category, notes.isEmpty ? nil : notes)
                        }
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedCategory = category ?? categories.first
                
                // Generate default filename with date
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                filename = "Scan \(formatter.string(from: Date()))"
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