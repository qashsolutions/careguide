//
//  WaitingForApprovalView.swift
//  HealthGuide
//
//  Shown to members waiting for admin approval to join a group
//

import SwiftUI

@available(iOS 18.0, *)
struct WaitingForApprovalView: View {
    let groupName: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupService = FirebaseGroupService.shared
    @State private var checkTimer: Timer?
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            // Animated waiting indicator
            VStack(spacing: AppTheme.Spacing.large) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                    .rotationEffect(.degrees(360))
                    .animation(
                        Animation.linear(duration: 3)
                            .repeatForever(autoreverses: false),
                        value: UUID()
                    )
                
                Text("Waiting for Approval")
                    .font(.monaco(AppTheme.ElderTypography.title))
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Text("Your request to join")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                Text(groupName)
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("is pending admin approval")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.screenPadding)
            
            VStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "bell")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                Text("You'll be notified once approved")
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
            }
            
            Spacer()
            
            // Option to cancel request
            Button(action: cancelRequest) {
                Text("Cancel Request")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.errorRed)
            }
            .padding(.bottom, AppTheme.Spacing.xxLarge)
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            startCheckingApprovalStatus()
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }
    
    private func startCheckingApprovalStatus() {
        // Check every 5 seconds if the request has been approved
        checkTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                let (hasPending, _) = await groupService.checkPendingJoinRequest()
                if !hasPending {
                    // Request was processed (approved or denied)
                    await MainActor.run {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func cancelRequest() {
        // TODO: Implement cancel request functionality
        dismiss()
    }
}

// MARK: - Preview
#Preview {
    WaitingForApprovalView(groupName: "Family Care Group")
}