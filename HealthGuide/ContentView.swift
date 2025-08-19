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
    
    // Trial status modal
    @State private var showTrialStatusModal = false
    @AppStorage("lastTrialModalShownDate") private var lastTrialModalShownDate: String = ""
    
    // Debug counter to track view recreations
    static var appearCount = 0
    
    // Removed init to prevent repeated initialization logs
    
    var body: some View {
        Group {
            // Stop rendering when backgrounded to save CPU
            if scenePhase == .background {
                Color.clear
                    .frame(width: 1, height: 1)
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
            
            // Check if we should show trial status modal
            checkTrialStatusModal()
        }
        .sheet(isPresented: $showTrialStatusModal) {
            TrialStatusModal(isPresented: $showTrialStatusModal)
                .environmentObject(subscriptionManager)
                .presentationDetents([.height(650), .large])  // Increased from 500 to 650 to show full content
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(cloudTrialManager.trialState?.isExpired ?? false) // Can't dismiss if expired
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkTrialStatusModal() {
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