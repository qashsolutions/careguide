//
//  AuthenticationView.swift
//  HealthGuide
//
//  Biometric authentication prompt view
//  Memory-efficient implementation using environment object
//

import SwiftUI

@available(iOS 18.0, *)
struct AuthenticationView: View {
    // Use EnvironmentObject instead of creating new StateObject to prevent memory issues
    @EnvironmentObject private var authManager: BiometricAuthManager
    @State private var isAuthenticating = false
    
    var body: some View {
        ZStack {
            // Warm off-white gradient background for reduced eye strain
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F8F8"),
                    Color(hex: "FAFAFA")
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.xxLarge) {
                Spacer()
                
                // App Icon - Shows your actual app logo for brand recognition
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                // Welcome Text
                VStack(spacing: AppTheme.Spacing.small) {
                    Text(AppStrings.App.welcome)
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .fontWeight(AppTheme.Typography.bold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(AppStrings.App.tagline)
                        .font(.monaco(AppTheme.ElderTypography.body))
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
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
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
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.errorRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.xxLarge)
                }
                
                Spacer()
                    .frame(height: AppTheme.Spacing.xxxLarge)
            }
        }
        .onAppear {
            // Only authenticate if not already authenticated
            if !authManager.isAuthenticated {
                authenticate()
            }
        }
    }
    
    @MainActor
    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        
        Task {
            _ = await authManager.authenticate(reason: " ")
            await MainActor.run {
                isAuthenticating = false
            }
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
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 64, height: 64)
                
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.monaco(AppTheme.ElderTypography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 100)
    }
}

// MARK: - Preview
#Preview {
    AuthenticationView()
        .environmentObject(BiometricAuthManager.shared)
}