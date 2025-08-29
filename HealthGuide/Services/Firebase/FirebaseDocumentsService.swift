//
//  FirebaseDocumentsService.swift
//  HealthGuide
//
//  Manages documents in Firebase for group sharing
//  Files are stored in Firebase Storage, metadata in Firestore
//

import Foundation
@preconcurrency import FirebaseFirestore
import FirebaseAuth
@preconcurrency import FirebaseStorage

// Note: FirestoreDocument model is defined in FirestoreModels.swift

@available(iOS 18.0, *)
@MainActor
final class FirebaseDocumentsService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseDocumentsService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private let storage = Storage.storage()
    
    @Published var isSyncing = false
    @Published var documents: [FirestoreDocument] = []
    @Published var syncError: Error?
    @Published var lastRefreshTime: Date?
    
    // Real-time listener
    private var documentsListener: ListenerRegistration?
    private var isListening = false
    
    // Dependencies
    private let groupService = FirebaseGroupService.shared
    
    // Current user's ID
    private var currentUserId: String? {
        return auth.currentUser?.uid
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🔥 FirebaseDocumentsService initialized")
        // Do NOT auto-load - FirebaseServiceManager will control initialization
    }
    
    // MARK: - Document Management
    
    /// Save document to Firebase (uploads file to Storage, metadata to Firestore)
    func saveDocument(
        filename: String,
        fileType: String,
        category: String?,
        fileData: Data,
        notes: String?
    ) async throws {
        guard let userId = currentUserId else {
            throw AppError.notAuthenticated
        }
        
        guard let group = groupService.currentGroup else {
            throw AppError.groupNotSet
        }
        
        // Check write permission
        guard groupService.userHasWritePermission else {
            throw AppError.noWritePermission
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        let documentId = UUID().uuidString
        let fileSize = Int64(fileData.count)
        
        // Upload file to Firebase Storage
        let storagePath = "groups/\(group.id)/documents/\(documentId)/\(filename)"
        let storageRef = storage.reference().child(storagePath)
        
        do {
            // Upload file with metadata
            let metadata = StorageMetadata()
            metadata.contentType = getContentType(for: fileType)
            
            // Upload data and wait for completion using completion handler
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                storageRef.putData(fileData, metadata: metadata) { metadata, error in
                    if let error = error {
                        AppLogger.main.error("Upload failed: \(error)")
                        continuation.resume(throwing: error)
                    } else if let metadata = metadata {
                        AppLogger.main.info("Upload succeeded - size: \(metadata.size) bytes")
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AppError.internalError("Upload failed - no metadata"))
                    }
                }
            }
            
            // Now get the download URL after confirmed upload
            let fileUrl = try await storageRef.downloadURL()
            
            // Save document metadata to Firestore
            let document = FirestoreDocument(
                id: documentId,
                groupId: group.id,
                filename: filename,
                fileType: fileType,
                category: category,
                fileSize: fileSize,
                storageUrl: fileUrl.absoluteString,
                notes: notes,
                createdBy: userId,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            try await db.collection("groups")
                .document(group.id)
                .collection("documents")
                .document(documentId)
                .setData(document.dictionary)
            
            AppLogger.main.info("✅ Document saved to Firebase: \(filename)")
            
            // Reload documents
            await loadDocuments()
        } catch {
            AppLogger.main.error("❌ Failed to save document: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Update document metadata
    func updateDocument(_ document: FirestoreDocument) async throws {
        guard currentUserId != nil else {
            throw AppError.notAuthenticated
        }
        
        guard let group = groupService.currentGroup else {
            throw AppError.groupNotSet
        }
        
        // Check write permission
        guard groupService.userHasWritePermission else {
            throw AppError.noWritePermission
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        var updatedDocument = document
        updatedDocument.updatedAt = Date()
        
        do {
            try await db.collection("groups")
                .document(group.id)
                .collection("documents")
                .document(document.id)
                .setData(updatedDocument.dictionary, merge: true)
            
            AppLogger.main.info("✅ Document updated in Firebase: \(document.filename)")
            
            // Reload documents
            await loadDocuments()
        } catch {
            AppLogger.main.error("❌ Failed to update document: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Delete document from Firebase (removes both file and metadata)
    func deleteDocument(_ documentId: String) async throws {
        guard currentUserId != nil else {
            throw AppError.notAuthenticated
        }
        
        guard let group = groupService.currentGroup else {
            throw AppError.groupNotSet
        }
        
        // Check write permission
        guard groupService.userHasWritePermission else {
            throw AppError.noWritePermission
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Get document to find storage URL
            let docSnapshot = try await db.collection("groups")
                .document(group.id)
                .collection("documents")
                .document(documentId)
                .getDocument()
            
            // Delete file from Storage if URL exists
            if let data = docSnapshot.data(),
               let filename = data["filename"] as? String {
                let storagePath = "groups/\(group.id)/documents/\(documentId)/\(filename)"
                let storageRef = storage.reference().child(storagePath)
                try await storageRef.delete()
            }
            
            // Delete document from Firestore
            try await db.collection("groups")
                .document(group.id)
                .collection("documents")
                .document(documentId)
                .delete()
            
            AppLogger.main.info("✅ Document deleted from Firebase")
            
            // Reload documents
            await loadDocuments()
        } catch {
            AppLogger.main.error("❌ Failed to delete document: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Load all documents from Firebase
    func loadDocuments() async {
        guard currentUserId != nil else {
            AppLogger.main.warning("⚠️ No authenticated user, skipping documents load")
            return
        }
        
        guard let group = groupService.currentGroup else {
            AppLogger.main.info("ℹ️ No group selected, clearing documents")
            await MainActor.run {
                self.documents = []
            }
            return
        }
        
        isSyncing = true
        defer { 
            Task { @MainActor in
                self.isSyncing = false
            }
        }
        
        do {
            let snapshot = try await db.collection("groups")
                .document(group.id)
                .collection("documents")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let loadedDocuments = snapshot.documents.compactMap { doc -> FirestoreDocument? in
                let data = doc.data()
                return FirestoreDocument(
                    documentId: doc.documentID,
                    id: data["id"] as? String ?? doc.documentID,
                    groupId: data["groupId"] as? String ?? group.id,
                    filename: data["filename"] as? String ?? "Unknown",
                    fileType: data["fileType"] as? String ?? "",
                    category: data["category"] as? String,
                    fileSize: data["fileSize"] as? Int64 ?? 0,
                    storageUrl: data["storageUrl"] as? String,
                    notes: data["notes"] as? String,
                    createdBy: data["createdBy"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
            
            await MainActor.run {
                self.documents = loadedDocuments
                self.lastRefreshTime = Date()
            }
            
            AppLogger.main.info("📊 Loaded \(loadedDocuments.count) documents from Firebase")
        } catch {
            AppLogger.main.error("❌ Failed to load documents: \(error)")
            await MainActor.run {
                self.syncError = error
            }
        }
    }
    
    /// Download document file
    func downloadDocument(_ document: FirestoreDocument) async throws -> Data {
        guard let storageUrl = document.storageUrl,
              !storageUrl.isEmpty else {
            throw AppError.internalError("No storage URL available")
        }
        
        // Download from Firebase Storage
        let storagePath = "groups/\(document.groupId)/documents/\(document.id)/\(document.filename)"
        let storageRef = storage.reference().child(storagePath)
        
        do {
            let maxSize: Int64 = 50 * 1024 * 1024 // 50MB max
            let data = try await storageRef.data(maxSize: maxSize)
            return data
        } catch {
            AppLogger.main.error("❌ Failed to download document: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Refresh documents if needed (e.g., if last refresh was more than an hour ago)
    func refreshIfNeeded() async {
        // Use global request deduplication
        guard FirebaseServiceManager.shared.shouldProceedWithRequest(service: "documents", operation: "refresh") else {
            return
        }
        defer {
            Task { @MainActor in
                FirebaseServiceManager.shared.completeRequest(service: "documents", operation: "refresh")
            }
        }
        
        let oneHour: TimeInterval = 3600
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < oneHour {
            // Skip refresh if less than an hour since last refresh
            AppLogger.main.info("⏭️ Skipping refresh - last refresh was \(Int(Date().timeIntervalSince(lastRefresh))) seconds ago")
            return
        }
        
        await loadDocuments()
    }
    
    // MARK: - Real-time Listener Management
    
    /// Start listening for real-time document changes
    func startListening() {
        guard !isListening else {
            AppLogger.main.info("⏭️ Documents listener already active")
            return
        }
        
        guard let group = groupService.currentGroup else {
            AppLogger.main.info("⚠️ No group selected, cannot start documents listener")
            return
        }
        
        // Check if user is still a member of the group
        guard let userId = Auth.auth().currentUser?.uid,
              group.memberIds.contains(userId) else {
            AppLogger.main.warning("🚫 User not authorized to access documents")
            documents = []  // Clear any cached data
            return
        }
        
        // Setup real-time listener
        documentsListener = db.collection("groups")
            .document(group.id)
            .collection("documents")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("❌ Documents listener error: \(error)")
                    Task { @MainActor in
                        self.syncError = error
                    }
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Process document changes
                let loadedDocuments = snapshot.documents.compactMap { doc -> FirestoreDocument? in
                    let data = doc.data()
                    return FirestoreDocument(
                        documentId: doc.documentID,
                        id: data["id"] as? String ?? doc.documentID,
                        groupId: data["groupId"] as? String ?? group.id,
                        filename: data["filename"] as? String ?? "Unknown",
                        fileType: data["fileType"] as? String ?? "",
                        category: data["category"] as? String,
                        fileSize: data["fileSize"] as? Int64 ?? 0,
                        storageUrl: data["storageUrl"] as? String,
                        notes: data["notes"] as? String,
                        createdBy: data["createdBy"] as? String ?? "",
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                
                Task { @MainActor in
                    self.documents = loadedDocuments
                    if !snapshot.metadata.isFromCache {
                        self.lastRefreshTime = Date()
                    }
                    AppLogger.main.info("📄 Documents updated via listener: \(loadedDocuments.count) items")
                }
            }
        
        isListening = true
        AppLogger.main.info("✅ Documents real-time listener started")
    }
    
    /// Stop listening for document changes
    func stopListening() {
        documentsListener?.remove()
        documentsListener = nil
        isListening = false
        AppLogger.main.info("🛑 Documents listener stopped")
    }
    
    // MARK: - Helper Methods
    
    private func getContentType(for fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "doc", "docx":
            return "application/msword"
        case "txt":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }
}