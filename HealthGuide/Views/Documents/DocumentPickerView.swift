//
//  DocumentPickerView.swift
//  HealthGuide
//
//  Simplified document picker that works properly with SwiftUI
//

import SwiftUI
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDocumentPicked: (URL, Int64) -> Void
    let onError: (String) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.pdf, .jpeg, .png, .heic]
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
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                parent.onError("Unable to access the selected file.")
                parent.isPresented = false
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
                    parent.onError("This file is \(sizeInMB) MB. Please choose a file smaller than 3 MB.")
                    parent.isPresented = false
                    return
                }
                
                parent.onDocumentPicked(url, fileSize)
                parent.isPresented = false
                
            } catch {
                parent.onError("Failed to process the selected file.")
                parent.isPresented = false
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}