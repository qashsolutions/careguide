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
    @State private var selectedTab = 0
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaymentPrompt = false
    
    // Cache views to prevent recreation
    @State private var hasInitialized = false
    
    // Removed init to prevent repeated initialization logs
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // MyHealth Tab
            NavigationStack {
                MyHealthDashboardView()
                    .navigationTitle(AppStrings.TabBar.myHealth)
            }
            .tabItem {
                Label(
                    title: { Text(AppStrings.TabBar.myHealth) },
                    icon: { 
                        Image(systemName: selectedTab == 0 ? "heart.text.clipboard.fill" : "heart.text.clipboard")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(0)
            
            // Groups Tab
            NavigationStack {
                GroupDashboardView()
                    .navigationTitle(AppStrings.TabBar.groups)
            }
            .tabItem {
                Label(
                    title: { Text(AppStrings.TabBar.groups) },
                    icon: { 
                        Image(systemName: selectedTab == 1 ? "person.3.fill" : "person.3")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(1)
            
            // Contacts Tab
            NavigationStack {
                ContactsView()
                    .navigationTitle(AppStrings.TabBar.contacts)
            }
            .tabItem {
                Label(
                    title: { Text(AppStrings.TabBar.contacts) },
                    icon: { 
                        Image(systemName: selectedTab == 2 ? "person.crop.circle.badge.checkmark.fill" : "person.crop.circle.badge.checkmark")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(2)
            
            // Memos Tab
            NavigationStack {
                CareMemosView()
                    .navigationTitle("Memos")
            }
            .tabItem {
                Label(
                    title: { Text("Memos") },
                    icon: { 
                        Image(systemName: selectedTab == 3 ? "mic.circle.fill" : "mic.circle")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(3)
            
            // Vault Tab
            NavigationStack {
                DocumentsView()
                    .navigationTitle("Vault")
            }
            .tabItem {
                Label(
                    title: { Text("Vault") },
                    icon: { 
                        Image(systemName: selectedTab == 4 ? "folder.fill" : "folder")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(4)
        }
        .tint(AppTheme.Colors.primaryBlue)
        .onAppear {
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
