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
    @State private var isAuthenticated = false
    
    var body: some View {
        mainContent
            .task {
                if biometricAuth.isBiometricEnabled {
                    await authenticate()
                } else {
                    isAuthenticated = true
                }
            }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if isAuthenticated || !biometricAuth.isBiometricEnabled {
            TabBarView()
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        } else {
            AuthenticationView()
        }
    }
    
    @MainActor
    private func authenticate() async {
        let success = await biometricAuth.authenticate()
        withAnimation {
            isAuthenticated = success
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
