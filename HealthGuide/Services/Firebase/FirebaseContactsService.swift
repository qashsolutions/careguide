//
//  FirebaseContactsService.swift
//  HealthGuide
//
//  Manages contacts data in Firebase for group sharing
//  Members have read-only access to group contacts
//

import Foundation
@preconcurrency import FirebaseFirestore
import FirebaseAuth

// Note: FirestoreContact model is defined in FirestoreModels.swift

@available(iOS 18.0, *)
@MainActor
final class FirebaseContactsService: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseContactsService()
    
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    
    @Published var isSyncing = false
    @Published var contacts: [FirestoreContact] = []
    @Published var syncError: Error?
    @Published var lastRefreshTime: Date?
    
    // Real-time listener
    private var contactsListener: ListenerRegistration?
    private var isListening = false
    
    // Dependencies
    private let groupService = FirebaseGroupService.shared
    
    // Current user's ID
    private var currentUserId: String? {
        return auth.currentUser?.uid
    }
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🔥 FirebaseContactsService initialized")
        // Do NOT auto-load - FirebaseServiceManager will control initialization
    }
    
    // MARK: - Contact Management
    
    /// Save contact to Firebase (group space)
    func saveContact(
        name: String,
        category: String?,
        phone: String?,
        isPrimary: Bool,
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
        
        let contactId = UUID().uuidString
        let contact = FirestoreContact(
            id: contactId,
            groupId: group.id,
            name: name,
            category: category,
            phone: phone,
            isPrimary: isPrimary,
            notes: notes,
            createdBy: userId,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        do {
            try await db.collection("groups")
                .document(group.id)
                .collection("contacts")
                .document(contactId)
                .setData(contact.dictionary)
            
            AppLogger.main.info("✅ Contact saved to Firebase: \(name)")
            
            // Reload contacts
            await loadContacts()
        } catch {
            AppLogger.main.error("❌ Failed to save contact: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Update existing contact
    func updateContact(_ contact: FirestoreContact) async throws {
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
        
        var updatedContact = contact
        updatedContact.updatedAt = Date()
        
        do {
            try await db.collection("groups")
                .document(group.id)
                .collection("contacts")
                .document(contact.id)
                .setData(updatedContact.dictionary, merge: true)
            
            AppLogger.main.info("✅ Contact updated in Firebase: \(contact.name)")
            
            // Reload contacts
            await loadContacts()
        } catch {
            AppLogger.main.error("❌ Failed to update contact: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Delete contact from Firebase
    func deleteContact(_ contactId: String) async throws {
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
            try await db.collection("groups")
                .document(group.id)
                .collection("contacts")
                .document(contactId)
                .delete()
            
            AppLogger.main.info("✅ Contact deleted from Firebase")
            
            // Reload contacts
            await loadContacts()
        } catch {
            AppLogger.main.error("❌ Failed to delete contact: \(error)")
            throw AppError.firebaseSyncFailed(reason: error.localizedDescription)
        }
    }
    
    /// Load all contacts from Firebase
    func loadContacts() async {
        guard currentUserId != nil else {
            AppLogger.main.warning("⚠️ No authenticated user, skipping contact load")
            return
        }
        
        guard let group = groupService.currentGroup else {
            AppLogger.main.info("ℹ️ No group selected, clearing contacts")
            await MainActor.run {
                self.contacts = []
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
                .collection("contacts")
                .order(by: "name")
                .getDocuments()
            
            let loadedContacts = snapshot.documents.compactMap { doc -> FirestoreContact? in
                let data = doc.data()
                return FirestoreContact(
                    documentId: doc.documentID,
                    id: data["id"] as? String ?? doc.documentID,
                    groupId: data["groupId"] as? String ?? group.id,
                    name: data["name"] as? String ?? "",
                    category: data["category"] as? String,
                    phone: data["phone"] as? String,
                    isPrimary: data["isPrimary"] as? Bool ?? false,
                    notes: data["notes"] as? String,
                    createdBy: data["createdBy"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
            
            await MainActor.run {
                self.contacts = loadedContacts
                self.lastRefreshTime = Date()
            }
            
            AppLogger.main.info("📊 Loaded \(loadedContacts.count) contacts from Firebase")
        } catch {
            AppLogger.main.error("❌ Failed to load contacts: \(error)")
            await MainActor.run {
                self.syncError = error
            }
        }
    }
    
    /// Refresh contacts if needed (e.g., if last refresh was more than an hour ago)
    func refreshIfNeeded() async {
        // Use global request deduplication
        guard FirebaseServiceManager.shared.shouldProceedWithRequest(service: "contacts", operation: "refresh") else {
            return
        }
        defer {
            Task { @MainActor in
                FirebaseServiceManager.shared.completeRequest(service: "contacts", operation: "refresh")
            }
        }
        
        let oneHour: TimeInterval = 3600
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < oneHour {
            // Skip refresh if less than an hour since last refresh
            AppLogger.main.info("⏭️ Skipping refresh - last refresh was \(Int(Date().timeIntervalSince(lastRefresh))) seconds ago")
            return
        }
        
        await loadContacts()
    }
    
    // MARK: - Real-time Listener Management
    
    /// Start listening for real-time contact changes
    func startListening() {
        guard !isListening else {
            AppLogger.main.info("⏭️ Contacts listener already active")
            return
        }
        
        guard let group = groupService.currentGroup else {
            AppLogger.main.info("⚠️ No group selected, cannot start contacts listener")
            return
        }
        
        // Check if user is still a member of the group
        guard let userId = Auth.auth().currentUser?.uid,
              group.memberIds.contains(userId) else {
            AppLogger.main.warning("🚫 User not authorized to access contacts")
            contacts = []  // Clear any cached data
            return
        }
        
        // Setup real-time listener
        contactsListener = db.collection("groups")
            .document(group.id)
            .collection("contacts")
            .order(by: "name")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.main.error("❌ Contacts listener error: \(error)")
                    Task { @MainActor in
                        self.syncError = error
                    }
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Process contact changes
                let loadedContacts = snapshot.documents.compactMap { doc -> FirestoreContact? in
                    let data = doc.data()
                    return FirestoreContact(
                        documentId: doc.documentID,
                        id: data["id"] as? String ?? doc.documentID,
                        groupId: data["groupId"] as? String ?? group.id,
                        name: data["name"] as? String ?? "",
                        category: data["category"] as? String,
                        phone: data["phone"] as? String,
                        isPrimary: data["isPrimary"] as? Bool ?? false,
                        notes: data["notes"] as? String,
                        createdBy: data["createdBy"] as? String ?? "",
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                
                Task { @MainActor in
                    self.contacts = loadedContacts
                    if !snapshot.metadata.isFromCache {
                        self.lastRefreshTime = Date()
                    }
                    AppLogger.main.info("📞 Contacts updated via listener: \(loadedContacts.count) items")
                }
            }
        
        isListening = true
        AppLogger.main.info("✅ Contacts real-time listener started")
    }
    
    /// Stop listening for contact changes
    func stopListening() {
        contactsListener?.remove()
        contactsListener = nil
        isListening = false
        AppLogger.main.info("🛑 Contacts listener stopped")
    }
}
