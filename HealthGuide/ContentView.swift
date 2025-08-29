//
//  ContentView.swift
//  HealthGuide
//
//  Created by Ramana Chinthapenta on 7/25/25.
//
//  Root view that manages authentication and navigation
//

import SwiftUI
import CoreData
import FirebaseAuth

@available(iOS 18.0, *)
struct ContentView: View {
    @EnvironmentObject private var biometricAuth: BiometricAuthManager
    @EnvironmentObject private var accessManager: AccessSessionManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @StateObject private var cloudTrialManager = CloudTrialManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    // Session start indicator
    @State private var showSessionStartIndicator = false
    @State private var sessionIndicatorScale: CGFloat = 0.5
    @State private var sessionIndicatorOpacity: Double = 0
    
    // Access revocation handling
    @State private var showAccessRevokedModal = false
    @State private var accessRevokedMessage = "Your access to this group has been revoked."
    @State private var permissionErrorCount = 0
    
    // Trial status modal
    @State private var showTrialStatusModal = false
    @State private var showJoinGroupPrompt = false
    @AppStorage("lastTrialModalShownDate") private var lastTrialModalShownDate: String = ""
    @AppStorage("hasCompletedGroupSetup") private var hasCompletedGroupSetup: Bool = false
    @AppStorage("isSecondaryUser") private var isSecondaryUser: Bool = false
    @AppStorage("hasSeenPrivacyNotice") private var hasSeenPrivacyNotice: Bool = false
    
    // Join request approval for admins
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @State private var showJoinRequestApproval = false
    @State private var currentJoinRequest: PendingJoinRequest?
    
    // Debug counter to track view recreations
    static var appearCount = 0
    
    // Removed init to prevent repeated initialization logs
    
    var body: some View {
        Group {
            // Stop rendering when backgrounded to save CPU
            if scenePhase == .background {
                Color.clear
                    .frame(width: 1, height: 1)
            } else if !hasSeenPrivacyNotice && biometricAuth.isAuthenticated {
                // Show privacy notice for first-time users after biometric setup
                PrivacyNoticeView(hasSeenPrivacyNotice: $hasSeenPrivacyNotice)
            } else if !hasCompletedGroupSetup && biometricAuth.isAuthenticated {
                // Show join prompt for NEW users after seeing privacy notice
                JoinGroupPromptView(
                    hasCompletedSetup: $hasCompletedGroupSetup,
                    isSecondaryUser: $isSecondaryUser
                )
                .environmentObject(subscriptionManager)
            } else if !accessManager.canAccess && !subscriptionManager.subscriptionState.isActive {
                DailyAccessLockView()
                    .onAppear {
                        print("⏱️ [VIEW] DailyAccessLockView appeared")
                        print("  - isCheckingAccess: \(accessManager.isCheckingAccess)")
                        print("  - canAccess: \(accessManager.canAccess)")
                        print("  - subscriptionActive: \(subscriptionManager.subscriptionState.isActive)")
                    }
                    .onDisappear {
                        print("⏱️ [VIEW] DailyAccessLockView disappeared")
                    }
            } else if biometricAuth.isAuthenticated || !biometricAuth.isBiometricEnabled {
                // Check if user still has valid group access
                if let group = FirebaseGroupService.shared.currentGroup,
                   let userId = Auth.auth().currentUser?.uid,
                   !group.memberIds.contains(userId) && !group.adminIds.contains(userId) {
                    // User no longer has access - show revoked view
                    AccessRevokedView(message: "Your access to this group has been revoked by the admin.")
                } else {
                    TabBarView()
                        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                        .onAppear {
                            print("⏱️ [VIEW] TabBarView appeared")
                            print("  - Can access: \(accessManager.canAccess)")
                            print("  - Is authenticated: \(biometricAuth.isAuthenticated)")
                            print("  - Biometric enabled: \(biometricAuth.isBiometricEnabled)")
                        }
                        .onDisappear {
                            print("⏱️ [VIEW] TabBarView disappeared")
                        }
                        .task {
                            // Start daily session if needed (trial users)
                            if accessManager.canAccess && subscriptionManager.subscriptionState.isInTrial {
                            let sessionStart = Date()
                            print("⏱️ [PERF] Starting daily session...")
                            print("🎯 Trial session indicator will show")
                            
                            // Show session start indicator for trial users
                            if subscriptionManager.trialSessionsRemaining > 0 {
                                await MainActor.run {
                                    showSessionStartIndicator = true
                                    // Animate in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        sessionIndicatorScale = 1.0
                                        sessionIndicatorOpacity = 1.0
                                    }
                                    // Animate out after delay
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                                        withAnimation(.easeIn(duration: 0.3)) {
                                            sessionIndicatorOpacity = 0
                                        }
                                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                                        showSessionStartIndicator = false
                                        sessionIndicatorScale = 0.5
                                    }
                                }
                            }
                            
                            await accessManager.startDailySession()
                            print("⏱️ [PERF] Daily session started in: \(Date().timeIntervalSince(sessionStart))s")
                        } else if accessManager.canAccess && !subscriptionManager.subscriptionState.isActive {
                            // Non-trial, non-subscription users get their daily session without indicator
                            await accessManager.startDailySession()
                        }
                        
                            // Notifications will be scheduled lazily when user has items
                            // This reduces CPU spike and memory usage at launch
                        }
                }
            } else {
                AuthenticationView()
                    .onAppear {
                        print("⏱️ [VIEW] AuthenticationView appeared")
                        print("  - Is authenticated: \(biometricAuth.isAuthenticated)")
                        print("  - Biometric enabled: \(biometricAuth.isBiometricEnabled)")
                    }
                    .onDisappear {
                        print("⏱️ [VIEW] AuthenticationView disappeared")
                    }
            }
        }
        .overlay {
            // Session start indicator overlay
            if showSessionStartIndicator {
                SessionStartIndicator(
                    scale: sessionIndicatorScale,
                    opacity: sessionIndicatorOpacity,
                    sessionsRemaining: subscriptionManager.trialSessionsRemaining
                )
                .allowsHitTesting(false) // Don't block user interaction
            }
        }
        .onAppear {
            ContentView.appearCount += 1
            print("⏱️ [VIEW] ContentView appeared (count: \(ContentView.appearCount))")
            print("  - Access checking: \(accessManager.isCheckingAccess)")
            print("  - Can access: \(accessManager.canAccess)")
            print("  - Subscription active: \(subscriptionManager.subscriptionState.isActive)")
            
            if ContentView.appearCount > 3 {
                print("⚠️ [PERF] WARNING: ContentView appeared \(ContentView.appearCount) times - possible view thrashing!")
            }
            
            // Configure navigation appearance to ensure titles are always black
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground
            appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().tintColor = UIColor.label
            
            // Check if we should show trial status modal
            checkTrialStatusModal()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowTrialModal"))) { _ in
            // Show trial modal when requested (after user chooses "Start Trial Instead")
            if hasCompletedGroupSetup {
                showTrialStatusModal = true
            }
        }
        .sheet(isPresented: $showTrialStatusModal) {
            TrialStatusModal(isPresented: $showTrialStatusModal)
                .environmentObject(subscriptionManager)
                .presentationDetents([.height(650), .large])  // Increased from 500 to 650 to show full content
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(cloudTrialManager.trialState?.isExpired ?? false) // Can't dismiss if expired
        }
        .fullScreenCover(isPresented: $showAccessRevokedModal) {
            AccessRevokedView(message: accessRevokedMessage)
        }
        .fullScreenCover(item: $currentJoinRequest) { request in
            JoinRequestApprovalView(request: request)
                .onDisappear {
                    // Check if there are more requests after handling this one
                    checkForNextJoinRequest()
                }
        }
        .onChange(of: firebaseGroups.pendingJoinRequests) { oldValue, newValue in
            // Show approval modal when new requests come in (admin only)
            if !newValue.isEmpty && currentJoinRequest == nil {
                currentJoinRequest = newValue.first
            }
        }
        .task {
            // Start listening for join requests if admin
            if firebaseGroups.userIsAdmin {
                firebaseGroups.startListeningForJoinRequests()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberAccessRevoked)) { notification in
            // Handle access revocation
            if let userInfo = notification.userInfo {
                // Get the message
                if let message = userInfo["message"] as? String {
                    accessRevokedMessage = message
                } else {
                    accessRevokedMessage = "Your access to this care group has been revoked by the admin."
                }
                
                // Check if this notification is for the current user
                if let memberId = userInfo["memberId"] as? String,
                   let currentUserId = Auth.auth().currentUser?.uid {
                    if memberId == currentUserId {
                        print("🚫 Current user's access was revoked - showing modal")
                        showAccessRevokedModal = true
                        hasCompletedGroupSetup = false
                    }
                } else {
                    // If we can't determine the user, but received the notification, assume it's for us
                    print("⚠️ Received access revoked notification without clear user match - showing modal")
                    showAccessRevokedModal = true
                    hasCompletedGroupSetup = false
                }
            }
            // If memberId doesn't match current user, ignore (admin revoking someone else's access)
        }
        .onReceive(NotificationCenter.default.publisher(for: .firebasePermissionDenied)) { _ in
            // Count permission errors - show modal after a few errors
            permissionErrorCount += 1
            if permissionErrorCount >= 2 && !showAccessRevokedModal {
                accessRevokedMessage = "You no longer have access to this care group"
                showAccessRevokedModal = true
                hasCompletedGroupSetup = false
            }
        }
        // Removed fullScreenCover - join prompt is shown inline for new users
    }
    
    // MARK: - Helper Methods
    
    private func checkForNextJoinRequest() {
        // If there are still pending requests, show the next one
        if let nextRequest = firebaseGroups.pendingJoinRequests.first(where: { $0.id != currentJoinRequest?.id }) {
            currentJoinRequest = nextRequest
        } else if !firebaseGroups.pendingJoinRequests.isEmpty {
            // If we still have requests but they might be the same, check the first one
            currentJoinRequest = firebaseGroups.pendingJoinRequests.first
        } else {
            currentJoinRequest = nil
        }
    }
    
    private func checkTrialStatusModal() {
        // Don't show trial modal if user hasn't completed setup (new users)
        guard hasCompletedGroupSetup else {
            // New users see the join prompt inline, not as a modal
            return
        }
        
        // Only show for trial users or expired trials
        guard let trialState = cloudTrialManager.trialState else { return }
        
        // Always show if trial is expired (hard paywall)
        if trialState.isExpired {
            showTrialStatusModal = true
            return
        }
        
        // Check if in trial
        guard subscriptionManager.subscriptionState.isInTrial else { return }
        
        // Check if we've already shown the modal today
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        
        if lastTrialModalShownDate != today {
            // Show modal after a short delay to not interfere with app launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showTrialStatusModal = true
                lastTrialModalShownDate = today
            }
        }
    }
}

// MARK: - Session Start Indicator
@available(iOS 18.0, *)
struct SessionStartIndicator: View {
    let scale: CGFloat
    let opacity: Double
    let sessionsRemaining: Int
    
    var body: some View {
        VStack(spacing: 12) {
            // Checkmark icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            // Session started text
            Text("Session Started")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            
            // Trial status - now unlimited
            Text("Unlimited trial access")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(radius: 10)
        )
        .scaleEffect(scale)
        .opacity(opacity)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(BiometricAuthManager.shared)
        .environmentObject(AccessSessionManager.shared)
        .environmentObject(SubscriptionManager.shared)
}