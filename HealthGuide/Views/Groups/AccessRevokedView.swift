//
//  AccessRevokedView.swift
//  HealthGuide
//
//  Blocking modal shown when member access is revoked
//  Guides caregivers to join another group or wait to create their own
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@available(iOS 18.0, *)
struct AccessRevokedView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupService = FirebaseGroupService.shared
    @State private var showJoinGroup = false
    @State private var cooldownDaysRemaining = 0
    @State private var canCreateGroup = true
    @State private var isCheckingEligibility = true
    let message: String
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with icon
                VStack(spacing: AppTheme.Spacing.large) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.Colors.warningOrange)
                    
                    Text("Group Access Changed")
                        .font(.monaco(AppTheme.ElderTypography.largeTitle))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
                .padding(.top, AppTheme.Spacing.xxLarge)
                
                // Message
                VStack(spacing: AppTheme.Spacing.medium) {
                    Text("You no longer have access to this care group")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.large)
                    
                    // Perfect for caregivers message
                    Text("Perfect for caregivers working with multiple families")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                        .italic()
                        .padding(.top, AppTheme.Spacing.small)
                    
                    Text("Your Options:")
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .padding(.top, AppTheme.Spacing.medium)
                    
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                        // Option 1: Join another group (always available)
                        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(AppTheme.Colors.successGreen)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Join Another Care Group")
                                    .font(.monaco(AppTheme.ElderTypography.body))
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                                    .fontWeight(.semibold)
                                Text("Get an invite code from another family")
                                    .font(.monaco(AppTheme.ElderTypography.footnote))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                        }
                        
                        // Option 2: Create own group (with cooldown check)
                        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(canCreateGroup ? AppTheme.Colors.primaryBlue : Color.gray)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                if isCheckingEligibility {
                                    Text("Checking eligibility...")
                                        .font(.monaco(AppTheme.ElderTypography.body))
                                        .foregroundColor(Color.gray)
                                } else if canCreateGroup {
                                    Text("Start Your Own Care Group")
                                        .font(.monaco(AppTheme.ElderTypography.body))
                                        .foregroundColor(AppTheme.Colors.textPrimary)
                                        .fontWeight(.semibold)
                                    Text("Begin your 14-day free trial")
                                        .font(.monaco(AppTheme.ElderTypography.footnote))
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                } else {
                                    Text("Start Your Own Care Group")
                                        .font(.monaco(AppTheme.ElderTypography.body))
                                        .foregroundColor(Color.gray)
                                        .strikethrough()
                                    Text("Available in \(cooldownDaysRemaining) days")
                                        .font(.monaco(AppTheme.ElderTypography.footnote))
                                        .foregroundColor(AppTheme.Colors.warningOrange)
                                    Text("(30-day waiting period after being a member)")
                                        .font(.monaco(AppTheme.ElderTypography.caption))
                                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.large)
                }
                .padding(.vertical, AppTheme.Spacing.xxLarge)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: AppTheme.Spacing.medium) {
                    // Primary action: Join another group
                    Button(action: {
                        showJoinGroup = true
                    }) {
                        HStack {
                            Image(systemName: "person.2.fill")
                            Text("Join Another Group")
                        }
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
                    .tint(AppTheme.Colors.successGreen)
                    
                    // Secondary action: Create group (if eligible)
                    if canCreateGroup && !isCheckingEligibility {
                        Button(action: {
                            // Navigate to Groups tab to create
                            dismiss()
                            // Post notification to navigate to Groups tab
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                NotificationCenter.default.post(name: .navigateToGroups, object: nil)
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create My Own Group")
                            }
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
                        .tint(AppTheme.Colors.primaryBlue)
                    }
                    
                    // Show waiting message if in cooldown
                    if !canCreateGroup && !isCheckingEligibility {
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 14))
                                Text("\(cooldownDaysRemaining) days until you can create a group")
                                    .font(.monaco(AppTheme.ElderTypography.caption))
                            }
                            .foregroundColor(AppTheme.Colors.warningOrange)
                            
                            Text("This prevents trial abuse")
                                .font(.monaco(AppTheme.ElderTypography.footnote))
                                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.7))
                        }
                        .padding(.vertical, AppTheme.Spacing.small)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.screenPadding)
                .padding(.bottom, AppTheme.Spacing.xxLarge)
            }
            .background(Color(hex: "F8F8F8"))
            .navigationBarHidden(true)
            .interactiveDismissDisabled(true) // Prevent dismissal by swiping
        }
        .sheet(isPresented: $showJoinGroup) {
            InviteCodeView(mode: .join, onSuccess: {
                // Dismiss the access revoked view after successfully joining
                dismiss()
            })
        }
        .task {
            await checkCreateGroupEligibility()
        }
    }
    
    // Check if user can create a group (30-day cooldown)
    private func checkCreateGroupEligibility() async {
        guard let userId = Auth.auth().currentUser?.uid else { 
            canCreateGroup = true
            isCheckingEligibility = false
            return 
        }
        
        do {
            // Get user's transition tracking data
            let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
            
            if let data = userDoc.data() {
                let lastTransitionAt = (data["lastTransitionAt"] as? Timestamp)?.dateValue()
                
                // Check cooldown (30 days)
                if let lastTransition = lastTransitionAt {
                    let daysSinceLastTransition = Calendar.current.dateComponents([.day], from: lastTransition, to: Date()).day ?? 0
                    if daysSinceLastTransition < 30 {
                        canCreateGroup = false
                        cooldownDaysRemaining = 30 - daysSinceLastTransition
                    } else {
                        canCreateGroup = true
                    }
                } else {
                    // No previous transition, eligible
                    canCreateGroup = true
                }
            } else {
                // No tracking data, eligible
                canCreateGroup = true
            }
        } catch {
            // Default to eligible on error
            canCreateGroup = true
        }
        
        isCheckingEligibility = false
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let navigateToGroups = Notification.Name("navigateToGroups")
}

// MARK: - Preview
#Preview {
    AccessRevokedView(message: "Your access to this group has been revoked by the admin.")
}