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
        ZStack {
            // Background color
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            // Content area with all tabs rendered
            VStack(spacing: 0) {
                // Main content
                ZStack {
                    // MyHealth Tab - Always rendered
                    NavigationStack {
                        MyHealthDashboardView()
                            .navigationTitle(AppStrings.TabBar.myHealth)
                    }
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(selectedTab == 0)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    
                    // Groups Tab - Always rendered
                    NavigationStack {
                        GroupDashboardView()
                            .navigationTitle(AppStrings.TabBar.groups)
                    }
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(selectedTab == 1)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    
                    // Contacts Tab - Always rendered
                    NavigationStack {
                        ContactsView()
                            .navigationTitle(AppStrings.TabBar.contacts)
                    }
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(selectedTab == 2)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    
                    // Memos Tab - Always rendered
                    NavigationStack {
                        CareMemosView()
                            .navigationTitle("Memos")
                    }
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(selectedTab == 3)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    
                    // Vault Tab - Always rendered
                    NavigationStack {
                        DocumentsView()
                            .navigationTitle("Vault")
                    }
                    .opacity(selectedTab == 4 ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(selectedTab == 4)
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
                
                // Custom Tab Bar
                customTabBar
            }
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
    
    // MARK: - Custom Tab Bar
    @ViewBuilder
    private var customTabBar: some View {
        VStack(spacing: 0) {
            // Separator line
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(UIColor.separator))
            
            HStack(spacing: 0) {
                // MyHealth Tab Button
                TabBarButton(
                    title: AppStrings.TabBar.myHealth,
                    icon: "heart.text.clipboard",
                    isSelected: selectedTab == 0,
                    action: { 
                        print("🔍 [PERF] Tab tapped: MyHealth")
                        selectedTab = 0 
                    }
                )
                
                // Groups Tab Button
                TabBarButton(
                    title: AppStrings.TabBar.groups,
                    icon: "person.3",
                    isSelected: selectedTab == 1,
                    action: { 
                        print("🔍 [PERF] Tab tapped: Groups")
                        selectedTab = 1 
                    }
                )
                
                // Contacts Tab Button
                TabBarButton(
                    title: AppStrings.TabBar.contacts,
                    icon: "person.crop.circle.badge.checkmark",
                    isSelected: selectedTab == 2,
                    action: { 
                        print("🔍 [PERF] Tab tapped: Contacts")
                        selectedTab = 2 
                    }
                )
                
                // Memos Tab Button
                TabBarButton(
                    title: "Memos",
                    icon: "mic.circle",
                    isSelected: selectedTab == 3,
                    action: { 
                        print("🔍 [PERF] Tab tapped: Memos")
                        selectedTab = 3 
                    }
                )
                
                // Vault Tab Button
                TabBarButton(
                    title: "Vault",
                    icon: "folder",
                    isSelected: selectedTab == 4,
                    action: { 
                        print("🔍 [PERF] Tab tapped: Vault")
                        selectedTab = 4 
                    }
                )
            }
            .padding(.top, 8) // Add small padding at top for breathing room
            .frame(height: 49) // Standard tab bar height
            .padding(.bottom) // This will automatically add safe area padding
        }
        .background(Color(UIColor.secondarySystemBackground).ignoresSafeArea())
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


// MARK: - Tab Bar Button Component
@available(iOS 18.0, *)
struct TabBarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary)
                
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 49)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#Preview {
    TabBarView()
}
