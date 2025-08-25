//
//  PrivacyNoticeView.swift
//  HealthGuide
//
//  Privacy notice shown on first launch - designed for 60+ caregivers
//

import SwiftUI

@available(iOS 18.0, *)
struct PrivacyNoticeView: View {
    @Binding var hasSeenPrivacyNotice: Bool
    
    var body: some View {
        ZStack {
            // Warm, trustworthy background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(hex: "F8F8F8"),
                    Color(hex: "FAFAFA")
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.large) {
                Spacer()
                    .frame(height: AppTheme.Spacing.xLarge)
                
                // Shield icon for trust
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 70))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                    .padding(.bottom, AppTheme.Spacing.medium)
                
                // Title
                Text("Your Privacy Matters")
                    .font(.monaco(AppTheme.ElderTypography.title))
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .padding(.bottom, AppTheme.Spacing.small)
                
                // Privacy points - clear for 60+ users
                VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                    PrivacyPoint(
                        icon: "envelope.badge.shield.half.filled",
                        text: "No email or phone needed",
                        subtext: "Login stays private and anonymous"
                    )
                    
                    PrivacyPoint(
                        icon: "person.crop.circle.badge.xmark",
                        text: "No personal information required",
                        subtext: "We never ask for names or addresses"
                    )
                    
                    PrivacyPoint(
                        icon: "eye.slash.fill",
                        text: "Your data stays private",
                        subtext: "Everything is stored anonymously"
                    )
                    
                    PrivacyPoint(
                        icon: "square.and.arrow.up",
                        text: "Export anytime",
                        subtext: "Your data belongs to you"
                    )
                }
                .padding(.horizontal, AppTheme.Spacing.xLarge)
                .padding(.vertical, AppTheme.Spacing.medium)
                
                Spacer()
                
                // Single clear button
                Button(action: {
                    hasSeenPrivacyNotice = true
                }) {
                    Text("I Understand")
                        .font(.monaco(AppTheme.ElderTypography.largeBody))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                }
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                        .fill(AppTheme.Colors.primaryBlue)
                )
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
                .padding(.bottom, AppTheme.Spacing.xxLarge)
            }
        }
    }
}

// Privacy point component
@available(iOS 18.0, *)
struct PrivacyPoint: View {
    let icon: String
    let text: String
    let subtext: String
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(AppTheme.Colors.successGreen)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(subtext)
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

@available(iOS 18.0, *)
struct PrivacyNoticeView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyNoticeView(hasSeenPrivacyNotice: .constant(false))
    }
}