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
    
    // Removed init to prevent repeated initialization logs
    
    var body: some View {
        Group {
            // Check access and authentication status
            if !accessManager.isCheckingAccess && !accessManager.canAccess && !subscriptionManager.subscriptionState.isActive {
                DailyAccessLockView()
                    .onAppear {
                        #if DEBUG
                        print("🚫 Showing DailyAccessLockView")
                        #endif
                    }
            } else if biometricAuth.isAuthenticated || !biometricAuth.isBiometricEnabled {
                TabBarView()
                    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                    .onAppear {
                        #if DEBUG
                        print("🏠 Showing TabBarView")
                        print("  - Can access: \(accessManager.canAccess)")
                        print("  - Is authenticated: \(biometricAuth.isAuthenticated)")
                        print("  - Biometric enabled: \(biometricAuth.isBiometricEnabled)")
                        #endif
                    }
                    .task {
                        // Start daily session if needed (basic users only)
                        if accessManager.canAccess && !subscriptionManager.subscriptionState.isActive {
                            #if DEBUG
                            print("📝 Starting daily session...")
                            #endif
                            await accessManager.startDailySession()
                        }
                    }
            } else {
                AuthenticationView()
                    .onAppear {
                        #if DEBUG
                        print("🔐 Showing AuthenticationView")
                        print("  - Is authenticated: \(biometricAuth.isAuthenticated)")
                        print("  - Biometric enabled: \(biometricAuth.isBiometricEnabled)")
                        #endif
                    }
            }
        }
        .onAppear {
            #if DEBUG
            print("📱 ContentView appeared")
            print("  - Access checking: \(accessManager.isCheckingAccess)")
            print("  - Can access: \(accessManager.canAccess)")
            print("  - Subscription active: \(subscriptionManager.subscriptionState.isActive)")
            #endif
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