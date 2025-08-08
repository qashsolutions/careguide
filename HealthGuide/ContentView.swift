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
    
    // Debug counter to track view recreations
    static var appearCount = 0
    
    // Removed init to prevent repeated initialization logs
    
    var body: some View {
        Group {
            // Check access and authentication status
            if !accessManager.isCheckingAccess && !accessManager.canAccess && !subscriptionManager.subscriptionState.isActive {
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
                        // Start daily session if needed (basic users only)
                        if accessManager.canAccess && !subscriptionManager.subscriptionState.isActive {
                            let sessionStart = Date()
                            print("⏱️ [PERF] Starting daily session...")
                            await accessManager.startDailySession()
                            print("⏱️ [PERF] Daily session started in: \(Date().timeIntervalSince(sessionStart))s")
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
        .onAppear {
            ContentView.appearCount += 1
            print("⏱️ [VIEW] ContentView appeared (count: \(ContentView.appearCount))")
            print("  - Access checking: \(accessManager.isCheckingAccess)")
            print("  - Can access: \(accessManager.canAccess)")
            print("  - Subscription active: \(subscriptionManager.subscriptionState.isActive)")
            
            if ContentView.appearCount > 3 {
                print("⚠️ [PERF] WARNING: ContentView appeared \(ContentView.appearCount) times - possible view thrashing!")
            }
        }
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