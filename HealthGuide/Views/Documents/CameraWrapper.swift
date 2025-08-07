//
//  CameraWrapper.swift
//  HealthGuide
//
//  Simplified camera interface that works with SwiftUI sheets
//

import SwiftUI
import AVFoundation

@available(iOS 18.0, *)
struct CameraWrapper: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let category: DocumentCategoryEntity?
    let onImageCaptured: (UIImage) -> Void
    
    @StateObject private var camera = CameraModel()
    @State private var showPermissionAlert = false
    
    var body: some View {
        CameraView(category: category)
            .environment(\.managedObjectContext, viewContext)
            .onAppear {
                // Set up the completion handler
                setupCameraHandlers()
            }
    }
    
    private func setupCameraHandlers() {
        // This would connect to the existing CameraView
        // For now, we'll modify the approach
    }
}

// Alternative: Simple camera capture using UIImagePickerController
@available(iOS 18.0, *)
struct SimpleCameraView: View {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage, Int64) -> Void
    let onError: (String) -> Void
    
    @State private var showCameraInfo = true
    @State private var showCamera = false
    
    var body: some View {
        ZStack {
            if showCameraInfo {
                CameraInfoView(
                    onContinue: {
                        showCameraInfo = false
                        showCamera = true
                    },
                    onCancel: {
                        isPresented = false
                    }
                )
            }
            
            if showCamera {
                SimpleCameraCapture(
                    isPresented: $isPresented,
                    onImageCaptured: onImageCaptured,
                    onError: onError
                )
                .ignoresSafeArea()
            }
        }
    }
}

// Camera info screen
@available(iOS 18.0, *)
struct CameraInfoView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color(hex: "F8F8F8").ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xxLarge) {
                Spacer()
                
                // Camera icon
                Image(systemName: "camera.fill")
                    .font(.system(size: 80))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                
                VStack(spacing: AppTheme.Spacing.large) {
                    Text("Photo Requirements")
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        Label("Maximum file size: 3 MB", systemImage: "doc.badge.arrow.up")
                            .font(.monaco(AppTheme.ElderTypography.body))
                        
                        Label("Clear, well-lit photos work best", systemImage: "light.max")
                            .font(.monaco(AppTheme.ElderTypography.body))
                        
                        Label("Hold camera steady for sharp images", systemImage: "camera.viewfinder")
                            .font(.monaco(AppTheme.ElderTypography.body))
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
                }
                
                Spacer()
                
                VStack(spacing: AppTheme.Spacing.medium) {
                    Button(action: onContinue) {
                        Text("Take Photo")
                            .font(.monaco(AppTheme.ElderTypography.callout))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.Dimensions.elderButtonHeight)
                            .background(AppTheme.Colors.primaryBlue)
                            .foregroundColor(.white)
                            .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                    }
                    
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.monaco(AppTheme.ElderTypography.callout))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
                
                Spacer()
            }
        }
    }
}

// Actual camera capture
@available(iOS 18.0, *)
struct SimpleCameraCapture: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage, Int64) -> Void
    let onError: (String) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SimpleCameraCapture
        
        init(_ parent: SimpleCameraCapture) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Compress image and get size
                if let imageData = image.jpegData(compressionQuality: 0.8) {
                    let fileSize = Int64(imageData.count)
                    
                    // Validate file size (3 MB limit)
                    if !DocumentEntity.isFileSizeValid(fileSize) {
                        // Try compressing more if it's too large
                        if let compressedData = image.jpegData(compressionQuality: 0.5) {
                            let compressedSize = Int64(compressedData.count)
                            if DocumentEntity.isFileSizeValid(compressedSize) {
                                parent.onImageCaptured(image, compressedSize)
                            } else {
                                parent.onError("Photo is too large (exceeds 3 MB). Please try taking a simpler photo with less detail.")
                            }
                        } else {
                            parent.onError("Unable to process photo. Please try again.")
                        }
                    } else {
                        parent.onImageCaptured(image, fileSize)
                    }
                }
            }
            
            parent.isPresented = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}