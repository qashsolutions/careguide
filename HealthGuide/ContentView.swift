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
    
    var body: some View {
        // Use BiometricAuthManager's isAuthenticated state directly
        // This prevents duplicate state and memory issues
        if biometricAuth.isAuthenticated || !biometricAuth.isBiometricEnabled {
            TabBarView()
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        } else {
            AuthenticationView()
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
