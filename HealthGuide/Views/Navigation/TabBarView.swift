//
//  TabBarView.swift
//  HealthGuide
//
//  Main navigation tab bar - elder-friendly design
//  Large icons, clear labels, simple navigation
//

import SwiftUI

@available(iOS 18.0, *)
struct TabBarView: View {
    @State private var selectedTab = 0 {
        didSet {
            print("🔍 [PERF] TabBarView - Tab switched from \(oldValue) to \(selectedTab)")
        }
    }
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaymentPrompt = false
    
    // Cache views to prevent recreation
    @State private var hasInitialized = false
    
    // Removed init to prevent repeated initialization logs
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MyHealthDashboardView()
                    .navigationTitle(AppStrings.TabBar.myHealth)
            }
            .tabItem {
                Label(AppStrings.TabBar.myHealth, systemImage: "heart.text.clipboard")
            }
            .tag(0)
            
            NavigationStack {
                GroupDashboardView()
                    .navigationTitle(AppStrings.TabBar.groups)
            }
            .tabItem {
                Label(AppStrings.TabBar.groups, systemImage: "person.3")
            }
            .tag(1)
            
            NavigationStack {
                ContactsView()
                    .navigationTitle(AppStrings.TabBar.contacts)
            }
            .tabItem {
                Label(AppStrings.TabBar.contacts, systemImage: "person.crop.circle.badge.checkmark")
            }
            .tag(2)
            
            NavigationStack {
                CareMemosView()
                    .navigationTitle("Memos")
            }
            .tabItem {
                Label("Memos", systemImage: "mic.circle")
            }
            .tag(3)
            
            NavigationStack {
                DocumentsView()
                    .navigationTitle("Vault")
            }
            .tabItem {
                Label("Vault", systemImage: "folder")
            }
            .tag(4)
        }
        .onAppear {
            print("🔍 [PERF] TabBarView.onAppear - hasInitialized: \(hasInitialized)")
            if !hasInitialized {
                setupTabBarAppearance()
                checkForPaymentPrompt()
                hasInitialized = true
            }
        }
        .sheet(isPresented: $showPaymentPrompt) {
            TrialPaymentPromptView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSubscriptionView)) { _ in
            // Show subscription view when notification is received
            selectedTab = 3 // Navigate to Settings tab
        }
    }
    
    // MARK: - Payment Prompt Check
    private func checkForPaymentPrompt() {
        // Check if we should show payment prompt (day 5+ of trial)
        if subscriptionManager.shouldShowPaymentPrompt {
            // Delay slightly to avoid sheet presentation conflicts
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showPaymentPrompt = true
            }
        }
    }
    
    // MARK: - Tab Bar Appearance
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // Background with blur effect
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor(AppTheme.Colors.backgroundPrimary.opacity(0.9))
        
        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(AppTheme.Colors.textSecondary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .font: UIFont(name: AppTheme.Typography.primaryFont, size: AppTheme.Typography.caption) ?? UIFont.systemFont(ofSize: AppTheme.Typography.caption),
            .foregroundColor: UIColor(AppTheme.Colors.textSecondary)
        ]
        
        // Selected state
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(AppTheme.Colors.primaryBlue)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: UIFont(name: AppTheme.Typography.primaryFont, size: AppTheme.Typography.caption) ?? UIFont.systemFont(ofSize: AppTheme.Typography.caption),
            .foregroundColor: UIColor(AppTheme.Colors.primaryBlue)
        ]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}




// MARK: - Preview
#Preview {
    TabBarView()
}
