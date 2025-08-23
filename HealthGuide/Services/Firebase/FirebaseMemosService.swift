//
//  FirebaseMemosService.swift
//  HealthGuide
//
//  Manages care memos in Firebase for group sharing
//  Audio files are stored in Firebase Storage, metadata in Firestore
//

import Foundation
@preconcurrency import FirebaseFirestore
import FirebaseAuth
@preconcurrency import FirebaseStorage

// Note: FirestoreCareMemo model is defined in FirestoreModels.swift

@available(iOS 18.0, *)
@MainActor
final class FirebaseMemosService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseMemosService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    private let storage = Storage.storage()
    
    @Published var isSyncing = false
    @Published var memos: [FirestoreCareMemo] = []
    @Published var syncError: Error?
    @Published var lastRefreshTime: Date?
    
    // Real-time listener
    private var memosListener: ListenerRegistration?
    private var isListening = false
    
    // Safety mechanisms to prevent recursive refresh
    private var isSavingMemo = false
    private var isDeletingMemo = false
    private var lastListenerUpdate: Date?
    private let minimumUpdateInterval: TimeInterval = 1.0 // Ignore updates within 1 second
    
    // Dependencies
    private let groupService = FirebaseGroupService.shared
    
    // Current user's ID
    private var currentUserId: String? {
        return auth.currentUser?.uid
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🔥 FirebaseMemosService initialized")
        // Do NOT auto-load - FirebaseServiceManager will control initialization
    }
    
    // MARK: - Memo Management
    
    /// Save memo to Firebase (uploads audio to Storage, metadata to Firestore)
    func saveMemo(
        title: String?,
        audioData: Data,
        duration: Double,
        transcription: String?,
        priority: String?,
        relatedMedicationIds: [String]?
    ) async throws {
        guard let userId = currentUserId else {
            throw AppError.notAuthenticated
        }
        
        guard let group = groupService.currentGroup else {
            throw AppError.groupNotSet
        }
        
        // Debug: Log current user and group permissions
        AppLogger.main.info("🔍 DEBUG - Memo Upload Permission Check:")
        AppLogger.main.info("   Current User ID: \(userId)")
        AppLogger.main.info("   Group ID: \(group.id)")
        AppLogger.main.info("   Group memberIds: \(group.memberIds)")
        AppLogger.main.info("   Group writePermissionIds: \(group.writePermissionIds)")
        AppLogger.main.info("   Group adminIds: \(group.adminIds)")
        AppLogger.main.info("   User has write permission: \(self.groupService.userHasWritePermission)")
        
        // Check write permission
        guard groupService.userHasWritePermission else {
            AppLogger.main.error("❌ User \(userId) does not have write permission")
            AppLogger.main.error("   Required: User ID must be in writePermissionIds array")
            throw AppError.noWritePermission
        }
        
        // Safety: Don't save if already saving
        guard !isSavingMemo else {
            AppLogger.main.warning("⚠️ Already saving a memo, skipping duplicate save")
            return
        }
        
        isSavingMemo = true
        isSyncing = true
        defer { 
            isSavingMemo = false
            isSyncing = false
        }
        
        let memoId = UUID().uuidString
        
        // Upload audio to Firebase Storage
        let audioPath = "groups/\(group.id)/memos/\(memoId).m4a"
        AppLogger.main.info("📤 Attempting to upload audio to path: \(audioPath)")
        AppLogger.main.info("📊 Audio data size: \(audioData.count) bytes")
        
        let storageRef = storage.reference().child(audioPath)
        
        do {
            // Upload audio file with metadata
            let metadata = StorageMetadata()
            metadata.contentType = "audio/m4a"
            
            AppLogger.main.info("🚀 Starting Firebase Storage upload...")
            AppLogger.main.info("🔐 Firebase Auth current user: \(self.auth.currentUser?.uid ?? "nil")")
            AppLogger.main.info("🔐 Auth user email: \(self.auth.currentUser?.email ?? "nil")")
            
            // Upload data and wait for completion using completion handler
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                _ = storageRef.putData(audioData, metadata: metadata) { metadata, error in
                    if let error = error {
                        AppLogger.main.error("❌ Storage upload failed: \(error)")
                        AppLogger.main.error("   Error domain: \((error as NSError).domain)")
                        AppLogger.main.error("   Error code: \((error as NSError).code)")
                        continuation.resume(throwing: error)
                    } else if let metadata = metadata {
                        AppLogger.main.info("✅ Storage upload succeeded!")
                        AppLogger.main.info("   File size: \(metadata.size) bytes")
                        AppLogger.main.info("   Content type: \(metadata.contentType ?? "unknown")")
                        AppLogger.main.info("   Path: \(metadata.path ?? "unknown")")
                        continuation.resume()
                    } else {
                        AppLogger.main.error("❌ Upload completed but no metadata returned")
                        continuation.resume(throwing: AppError.internalError("Upload failed - no metadata"))
                    }
                }
                
                // Log upload task state
                AppLogger.main.info("📝 Upload task created, observing progress...")
            }
            
            // Now get the download URL after confirmed upload
            AppLogger.main.info("🔗 Getting download URL for uploaded file...")
            let audioUrl = try await storageRef.downloadURL()
            AppLogger.main.info("✅ Got download URL: \(audioUrl.absoluteString)")
            
            // Save memo metadata to Firestore
            let memo = FirestoreCareMemo(
                id: memoId,
                groupId: group.id,
                title: title,
                audioStorageUrl: audioUrl.absoluteString,
                duration: duration,
                recordedAt: Date(),
                transcription: transcription,
                priority: priority,
                relatedMedicationIds: relatedMedicationIds,
                createdBy: userId,
                createdAt: Date()
            )
            
            try await db.collection("groups")
                .document(group.id)
                .collection("memos")
                .document(memoId)
                .setData(memo.dictionary)
            
            AppLogger.main.info("✅ Memo saved to Firebase with audio")
            
            // Don't reload - real-time listener will handle it
            // await loadMemos() - REMOVED to prevent recursive refresh
        } catch {
            AppLogger.main.error("❌ Failed to save memo: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Delete memo from Firebase (removes both audio and metadata)
    func deleteMemo(_ memoId: String) async throws {
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
        
        // Safety: Don't delete if already deleting
        guard !isDeletingMemo else {
            AppLogger.main.warning("⚠️ Already deleting a memo, skipping duplicate delete")
            return
        }
        
        isDeletingMemo = true
        isSyncing = true
        defer { 
            isDeletingMemo = false
            isSyncing = false
        }
        
        do {
            // Get memo to find audio URL
            let memoDoc = try await db.collection("groups")
                .document(group.id)
                .collection("memos")
                .document(memoId)
                .getDocument()
            
            // Delete audio from Storage if URL exists
            if let data = memoDoc.data(),
               let audioUrl = data["audioStorageUrl"] as? String,
               !audioUrl.isEmpty {
                // Parse the storage path from the URL
                let audioPath = "groups/\(group.id)/memos/\(memoId).m4a"
                let storageRef = storage.reference().child(audioPath)
                try await storageRef.delete()
            }
            
            // Delete memo document from Firestore
            try await db.collection("groups")
                .document(group.id)
                .collection("memos")
                .document(memoId)
                .delete()
            
            AppLogger.main.info("✅ Memo deleted from Firebase")
            
            // Don't reload - real-time listener will handle it  
            // await loadMemos() - REMOVED to prevent recursive refresh
        } catch {
            AppLogger.main.error("❌ Failed to delete memo: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Load all memos from Firebase
    func loadMemos() async {
        guard currentUserId != nil else {
            AppLogger.main.warning("⚠️ No authenticated user, skipping memos load")
            return
        }
        
        guard let group = groupService.currentGroup else {
            AppLogger.main.info("ℹ️ No group selected, clearing memos")
            await MainActor.run {
                self.memos = []
            }
            return
        }
        
        isSyncing = true
        defer { 
            isSyncing = false
        }
        
        do {
            let snapshot = try await db.collection("groups")
                .document(group.id)
                .collection("memos")
                .order(by: "recordedAt", descending: true)
                .getDocuments()
            
            let loadedMemos = snapshot.documents.compactMap { doc -> FirestoreCareMemo? in
                let data = doc.data()
                return FirestoreCareMemo(
                    documentId: doc.documentID,
                    id: data["id"] as? String ?? doc.documentID,
                    groupId: data["groupId"] as? String ?? group.id,
                    title: data["title"] as? String,
                    audioStorageUrl: data["audioStorageUrl"] as? String,
                    duration: data["duration"] as? Double ?? 0,
                    recordedAt: (data["recordedAt"] as? Timestamp)?.dateValue() ?? Date(),
                    transcription: data["transcription"] as? String,
                    priority: data["priority"] as? String,
                    relatedMedicationIds: data["relatedMedicationIds"] as? [String],
                    createdBy: data["createdBy"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
            
            await MainActor.run {
                self.memos = loadedMemos
                self.lastRefreshTime = Date()
            }
            
            AppLogger.main.info("📊 Loaded \(loadedMemos.count) memos from Firebase")
        } catch {
            AppLogger.main.error("❌ Failed to load memos: \(error)")
            await MainActor.run {
                self.syncError = error
            }
        }
    }
    
    /// Download audio data for a memo
    func downloadAudio(for memo: FirestoreCareMemo) async throws -> Data {
        guard let audioUrl = memo.audioStorageUrl,
              !audioUrl.isEmpty else {
            throw AppError.internalError("No audio URL available")
        }
        
        // Download from Firebase Storage
        let audioPath = "groups/\(memo.groupId)/memos/\(memo.id).m4a"
        let storageRef = storage.reference().child(audioPath)
        
        do {
            let maxSize: Int64 = 10 * 1024 * 1024 // 10MB max
            let data = try await storageRef.data(maxSize: maxSize)
            return data
        } catch {
            AppLogger.main.error("❌ Failed to download audio: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    // REMOVED refreshIfNeeded() method - manual refresh not needed
    // Real-time listeners handle all updates automatically
    // Periodic refresh (3600s) is managed by FirebaseServiceManager
    
    // MARK: - Real-time Listener Management
    
    /// Start listening for real-time memo changes
    func startListening() {
        // Safety: Ensure we don't create duplicate listeners
        guard !isListening else {
            AppLogger.main.info("⏭️ Memos listener already active")
            return
        }
        
        // Extra safety: Remove any existing listener before creating new one
        if memosListener != nil {
            AppLogger.main.warning("⚠️ Found orphaned listener, removing it")
            memosListener?.remove()
            memosListener = nil
        }
        
        guard let group = groupService.currentGroup else {
            AppLogger.main.info("⚠️ No group selected, cannot start memos listener")
            return
        }
        
        // Setup real-time listener
        memosListener = db.collection("groups")
            .document(group.id)
            .collection("memos")
            .order(by: "recordedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("❌ Memos listener error: \(error)")
                    Task { @MainActor in
                        self.syncError = error
                    }
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Process memo changes
                let loadedMemos = snapshot.documents.compactMap { doc -> FirestoreCareMemo? in
                    let data = doc.data()
                    return FirestoreCareMemo(
                        documentId: doc.documentID,
                        id: data["id"] as? String ?? doc.documentID,
                        groupId: data["groupId"] as? String ?? group.id,
                        title: data["title"] as? String,
                        audioStorageUrl: data["audioStorageUrl"] as? String,
                        duration: data["duration"] as? Double ?? 0,
                        recordedAt: (data["recordedAt"] as? Timestamp)?.dateValue() ?? Date(),
                        transcription: data["transcription"] as? String,
                        priority: data["priority"] as? String,
                        relatedMedicationIds: data["relatedMedicationIds"] as? [String],
                        createdBy: data["createdBy"] as? String ?? "",
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                
                Task { @MainActor in
                    // Safety: Debounce rapid updates
                    if let lastUpdate = self.lastListenerUpdate,
                       Date().timeIntervalSince(lastUpdate) < self.minimumUpdateInterval {
                        AppLogger.main.debug("⏭️ Ignoring rapid listener update (within 1 second)")
                        return
                    }
                    
                    // Safety: Don't update if we're in the middle of saving/deleting
                    if self.isSavingMemo || self.isDeletingMemo {
                        AppLogger.main.debug("⏭️ Skipping listener update during save/delete operation")
                        return
                    }
                    
                    self.memos = loadedMemos
                    self.lastListenerUpdate = Date()
                    if !snapshot.metadata.isFromCache {
                        self.lastRefreshTime = Date()
                    }
                    AppLogger.main.info("🎤 Memos updated via listener: \(loadedMemos.count) items")
                }
            }
        
        isListening = true
        AppLogger.main.info("✅ Memos real-time listener started")
    }
    
    /// Stop listening for memo changes
    func stopListening() {
        memosListener?.remove()
        memosListener = nil
        isListening = false
        AppLogger.main.info("🛑 Memos listener stopped")
    }
}
