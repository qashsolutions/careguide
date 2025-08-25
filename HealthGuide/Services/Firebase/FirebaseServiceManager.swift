//
//  FirebaseServiceManager.swift
//  HealthGuide
//
//  Centralized manager for all Firebase service listeners
//  Prevents infinite loops and ensures proper initialization for secondary users
//

import Foundation
import Combine

@available(iOS 18.0, *)
@MainActor
final class FirebaseServiceManager: ObservableObject {
    
    // MARK: - Singleton
    static let shared = FirebaseServiceManager()
    
    // MARK: - Properties
    @Published var isInitialized = false
    @Published var areListenersActive = false
    @Published var lastFullRefreshTime: Date?
    
    // Service references
    private let groupService = FirebaseGroupService.shared
    private let documentsService = FirebaseDocumentsService.shared
    private let contactsService = FirebaseContactsService.shared
    private let memosService = FirebaseMemosService.shared
    
    // Listener state tracking
    private var activeListeners: Set<String> = []
    private var refreshTimer: Timer?
    
    // Debouncing
    private var groupChangeDebouncer: AnyCancellable?
    private let debounceInterval: TimeInterval = 2.0 // 2 seconds debounce
    
    // Refresh interval (1 hour as per requirement)
    private let fullRefreshInterval: TimeInterval = 3600
    
    // MARK: - Request Deduplication
    // Track active requests to prevent duplicates
    private struct RequestFingerprint: Hashable {
        let service: String
        let operation: String
        let groupId: String?
        
        init(service: String, operation: String, groupId: String? = nil) {
            self.service = service
            self.operation = operation
            self.groupId = groupId ?? "default"
        }
    }
    
    private var activeRequests: Set<RequestFingerprint> = []
    private var requestTimeouts: [RequestFingerprint: Task<Void, Never>] = [:]
    private let requestTimeout: TimeInterval = 30 // 30 seconds timeout
    private let requestLock = NSLock()
    
    // MARK: - Initialization
    private init() {
        AppLogger.main.info("🎯 FirebaseServiceManager initialized")
        setupGroupChangeListener()
    }
    
    // MARK: - Group Change Handling (Debounced)
    private func setupGroupChangeListener() {
        // Listen for group changes with debouncing to prevent infinite loops
        groupChangeDebouncer = NotificationCenter.default
            .publisher(for: .firebaseGroupDidChange)
            .debounce(for: .seconds(debounceInterval), scheduler: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    AppLogger.main.info("🔄 Debounced group change detected")
                    
                    // Check if this is a group join or leave
                    if self.groupService.currentGroup != nil {
                        // User joined or switched groups
                        await self.handleGroupJoined()
                    } else {
                        // User left group
                        await self.handleGroupLeft()
                    }
                }
            }
    }
    
    // MARK: - Group Join/Leave Handlers
    
    /// Called when user joins a group - initializes all services
    private func handleGroupJoined() async {
        guard let group = groupService.currentGroup else { return }
        
        AppLogger.main.info("👥 User joined group: \(group.name)")
        AppLogger.main.info("   Initializing all Firebase services...")
        
        // Initialize all services in parallel
        await withTaskGroup(of: Void.self) { group in
            // Start listeners for each service
            group.addTask { [weak self] in
                await self?.startDocumentsListener()
            }
            
            group.addTask { [weak self] in
                await self?.startContactsListener()
            }
            
            group.addTask { [weak self] in
                await self?.startMemosListener()
            }
            
            // Wait for all to complete
            await group.waitForAll()
        }
        
        areListenersActive = true
        isInitialized = true
        
        // Schedule periodic refresh (every hour)
        schedulePeriodicRefresh()
        
        AppLogger.main.info("✅ All Firebase services initialized for group")
    }
    
    /// Called when user leaves a group - cleanup all listeners
    private func handleGroupLeft() async {
        AppLogger.main.info("👋 User left group, cleaning up services...")
        
        // Stop all listeners
        await stopAllListeners()
        
        // Cancel refresh timer
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        areListenersActive = false
        
        AppLogger.main.info("✅ All Firebase services cleaned up")
    }
    
    // MARK: - Service Listener Management
    
    private func startDocumentsListener() async {
        guard !activeListeners.contains("documents") else {
            AppLogger.main.info("⏭️ Documents listener already active - reloading data for current group")
            // Even if listener is active, reload data for the current group
            await documentsService.loadDocuments()
            return
        }
        
        // Start real-time listener
        documentsService.startListening()
        // Load initial data
        await documentsService.loadDocuments()
        activeListeners.insert("documents")
        
        AppLogger.main.info("📄 Documents listener started")
    }
    
    private func startContactsListener() async {
        guard !activeListeners.contains("contacts") else {
            AppLogger.main.info("⏭️ Contacts listener already active - reloading data for current group")
            // Even if listener is active, reload data for the current group
            await contactsService.loadContacts()
            return
        }
        
        // Start real-time listener
        contactsService.startListening()
        // Load initial data
        await contactsService.loadContacts()
        activeListeners.insert("contacts")
        
        AppLogger.main.info("📞 Contacts listener started")
    }
    
    private func startMemosListener() async {
        guard !activeListeners.contains("memos") else {
            AppLogger.main.info("⏭️ Memos listener already active - reloading data for current group")
            // Even if listener is active, reload data for the current group
            await memosService.loadMemos()
            return
        }
        
        // Start real-time listener
        memosService.startListening()
        // Load initial data
        await memosService.loadMemos()
        activeListeners.insert("memos")
        
        AppLogger.main.info("🎤 Memos listener started")
    }
    
    func stopAllListeners() async {
        // Stop all real-time listeners
        documentsService.stopListening()
        contactsService.stopListening()
        memosService.stopListening()
        
        activeListeners.removeAll()
        AppLogger.main.info("🛑 All listeners stopped")
    }
    
    // MARK: - Periodic Refresh (Every 3600 seconds)
    
    private func schedulePeriodicRefresh() {
        // Cancel existing timer if any
        refreshTimer?.invalidate()
        
        // Schedule refresh every hour
        refreshTimer = Timer.scheduledTimer(withTimeInterval: fullRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performFullRefresh()
            }
        }
        
        AppLogger.main.info("⏰ Scheduled periodic refresh every \(Int(self.fullRefreshInterval)) seconds")
    }
    
    /// Perform a full data refresh (called every hour)
    func performFullRefresh() async {
        guard groupService.currentGroup != nil else {
            AppLogger.main.info("⏭️ Skipping refresh - no active group")
            return
        }
        
        AppLogger.main.info("🔄 Starting full data refresh (3600-second interval)")
        
        // Refresh all services in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.documentsService.loadDocuments()
            }
            
            group.addTask { [weak self] in
                await self?.contactsService.loadContacts()
            }
            
            group.addTask { [weak self] in
                await self?.memosService.loadMemos()
            }
            
            await group.waitForAll()
        }
        
        lastFullRefreshTime = Date()
        
        AppLogger.main.info("✅ Full data refresh completed")
    }
    
    // MARK: - Manual Controls
    
    /// Manually initialize services (for testing or recovery)
    func initializeServicesIfNeeded() async {
        guard !isInitialized, groupService.currentGroup != nil else { return }
        await handleGroupJoined()
    }
    
    /// Force refresh all data (bypasses 3600-second throttle)
    func forceRefreshAllData() async {
        await performFullRefresh()
    }
    
    // MARK: - Request Deduplication Methods
    
    /// Check if a request should proceed or be skipped
    func shouldProceedWithRequest(service: String, operation: String) -> Bool {
        let fingerprint = RequestFingerprint(
            service: service,
            operation: operation,
            groupId: groupService.currentGroup?.id
        )
        
        requestLock.lock()
        defer { requestLock.unlock() }
        
        // Check if request is already active
        if activeRequests.contains(fingerprint) {
            AppLogger.main.info("🚫 Duplicate request blocked: \(service).\(operation)")
            return false
        }
        
        // Add to active requests
        activeRequests.insert(fingerprint)
        
        // Set timeout to clear stuck requests
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.requestTimeout ?? 30) * 1_000_000_000)
            self?.clearRequest(fingerprint)
            AppLogger.main.warning("⏱️ Request timeout cleared: \(service).\(operation)")
        }
        requestTimeouts[fingerprint] = timeoutTask
        
        AppLogger.main.debug("✅ Request proceeding: \(service).\(operation)")
        return true
    }
    
    /// Mark a request as completed
    func completeRequest(service: String, operation: String) {
        let fingerprint = RequestFingerprint(
            service: service,
            operation: operation,
            groupId: groupService.currentGroup?.id
        )
        
        clearRequest(fingerprint)
        AppLogger.main.debug("✅ Request completed: \(service).\(operation)")
    }
    
    /// Clear a request from tracking
    private func clearRequest(_ fingerprint: RequestFingerprint) {
        requestLock.lock()
        defer { requestLock.unlock() }
        
        activeRequests.remove(fingerprint)
        requestTimeouts[fingerprint]?.cancel()
        requestTimeouts.removeValue(forKey: fingerprint)
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        groupChangeDebouncer?.cancel()
        groupChangeDebouncer = nil
        activeListeners.removeAll()
        areListenersActive = false
        isInitialized = false
        
        // Clear all active requests
        requestLock.lock()
        activeRequests.removeAll()
        requestTimeouts.values.forEach { $0.cancel() }
        requestTimeouts.removeAll()
        requestLock.unlock()
        
        AppLogger.main.info("🧹 FirebaseServiceManager cleaned up")
    }
}