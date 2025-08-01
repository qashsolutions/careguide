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
    @StateObject private var authManager = BiometricAuthManager.shared
    
    init() {
        print("🔧 TabBarView: Initializing...")
    }
    
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
                        Image(systemName: selectedTab == 0 ? "heart.text.square.fill" : "heart.text.square")
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
                        Image(systemName: selectedTab == 2 ? "phone.circle.fill" : "phone.circle")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(2)
            
            // Conflicts Tab
            NavigationStack {
                ConflictsView()
                    .navigationTitle(AppStrings.TabBar.conflicts)
            }
            .tabItem {
                Label(
                    title: { Text(AppStrings.TabBar.conflicts) },
                    icon: { 
                        Image(systemName: selectedTab == 3 ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                            .font(.system(size: AppTheme.Dimensions.tabIconSize))
                    }
                )
            }
            .tag(3)
        }
        .tint(AppTheme.Colors.primaryBlue)
        .onAppear {
            setupTabBarAppearance()
        }
        .fullScreenCover(isPresented: .constant(!authManager.isAuthenticated)) {
            AuthenticationView()
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

// MARK: - Authentication View
@available(iOS 18.0, *)
struct AuthenticationView: View {
    @StateObject private var authManager = BiometricAuthManager.shared
    @State private var isAuthenticating = false
    
    var body: some View {
        ZStack {
            // Background
            AppTheme.Colors.backgroundPrimary
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xxLarge) {
                Spacer()
                
                // App Icon
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                
                // Welcome Text
                VStack(spacing: AppTheme.Spacing.small) {
                    Text(AppStrings.App.welcome)
                        .font(.monaco(AppTheme.Typography.title))
                        .fontWeight(AppTheme.Typography.bold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(AppStrings.App.tagline)
                        .font(.monaco(AppTheme.Typography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.xxLarge)
                }
                
                // Feature Icons
                HStack(spacing: AppTheme.Spacing.large) {
                    FeatureIconView(
                        icon: "brain.head.profile",
                        title: "Smart Health",
                        color: AppTheme.Colors.primaryBlue
                    )
                    
                    FeatureIconView(
                        icon: "person.3.fill",
                        title: "Care Groups",
                        color: AppTheme.Colors.successGreen
                    )
                    
                    FeatureIconView(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "Key Contacts",
                        color: AppTheme.Colors.warningOrange
                    )
                }
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
                
                Spacer()
                
                // Authentication Button
                Button(action: authenticate) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: authManager.biometricType.iconName)
                        Text(authManager.biometricType.displayName)
                    }
                    .font(.monaco(AppTheme.Typography.body))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                            .fill(AppTheme.Colors.primaryBlue)
                    )
                    .shadow(
                        color: AppTheme.Colors.primaryBlue.opacity(AppTheme.Effects.buttonShadowOpacity),
                        radius: AppTheme.Effects.buttonShadowRadius,
                        x: 0,
                        y: 4
                    )
                }
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
                .disabled(isAuthenticating)
                
                // Error Message
                if let error = authManager.authError {
                    Text(error.errorDescription ?? "")
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.errorRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.xxLarge)
                }
                
                Spacer()
                    .frame(height: AppTheme.Spacing.xxxLarge)
            }
        }
        .onAppear {
            authenticate()
        }
    }
    
    private func authenticate() {
        isAuthenticating = true
        Task {
            _ = await authManager.authenticate(reason: AppStrings.Auth.useFaceID)
            isAuthenticating = false
        }
    }
}

// MARK: - Feature Icon View
@available(iOS 18.0, *)
struct FeatureIconView: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.monaco(AppTheme.Typography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview {
    TabBarView()
}