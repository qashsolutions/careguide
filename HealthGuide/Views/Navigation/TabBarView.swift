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
