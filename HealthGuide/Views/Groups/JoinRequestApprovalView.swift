//
//  JoinRequestApprovalView.swift
//  HealthGuide
//
//  Modal shown to admin when there are pending join requests
//  Must approve or deny before continuing
//

import SwiftUI
import FirebaseAuth

@available(iOS 18.0, *)
struct JoinRequestApprovalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupService = FirebaseGroupService.shared
    
    let request: PendingJoinRequest
    @State private var isProcessing = false
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: AppTheme.Spacing.large) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                    
                    Text("New Join Request")
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
                .padding(.top, AppTheme.Spacing.xxLarge)
                
                // Request Details
                VStack(spacing: AppTheme.Spacing.large) {
                    VStack(spacing: AppTheme.Spacing.small) {
                        Text("Someone wants to join your care group")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        // Member name
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            Text(request.userName)
                                .font(.monaco(AppTheme.ElderTypography.headline))
                                .foregroundColor(AppTheme.Colors.textPrimary)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, AppTheme.Spacing.medium)
                        .padding(.horizontal, AppTheme.Spacing.large)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .fill(Color.gray.opacity(0.1))
                        )
                        
                        // Request time
                        Text("Requested \(timeAgo(from: request.requestedAt))")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                    }
                    
                    // Warning about member limit
                    if groupService.currentGroup?.memberIds.count ?? 0 >= 2 {
                        HStack(spacing: AppTheme.Spacing.small) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.Colors.warningOrange)
                            Text("Approving will reach the 3 member limit")
                                .font(.monaco(AppTheme.ElderTypography.footnote))
                                .foregroundColor(AppTheme.Colors.warningOrange)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                                .fill(AppTheme.Colors.warningOrange.opacity(0.1))
                        )
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxLarge)
                .padding(.horizontal, AppTheme.Spacing.screenPadding)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: AppTheme.Spacing.medium) {
                    // Approve button
                    Button(action: handleApprove) {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Approve & Add Member")
                        }
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
                    .tint(AppTheme.Colors.successGreen)
                    .disabled(isProcessing)
                    
                    // Deny button
                    Button(action: handleDeny) {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Deny Request")
                        }
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppTheme.Dimensions.buttonCornerRadius))
                    .tint(AppTheme.Colors.errorRed)
                    .disabled(isProcessing)
                    
                    Text("You must approve or deny this request to continue")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, AppTheme.Spacing.small)
                }
                .padding(.horizontal, AppTheme.Spacing.screenPadding)
                .padding(.bottom, AppTheme.Spacing.xxLarge)
            }
            .background(Color(UIColor.systemBackground))
            .navigationBarHidden(true)
            .interactiveDismissDisabled(true) // Cannot dismiss without handling request
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
                .foregroundColor(AppTheme.Colors.primaryBlue)
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleApprove() {
        isProcessing = true
        
        Task {
            do {
                try await groupService.approveJoinRequest(request.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func handleDeny() {
        isProcessing = true
        
        Task {
            do {
                try await groupService.denyJoinRequest(request.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Preview
#Preview {
    JoinRequestApprovalView(
        request: PendingJoinRequest(
            id: "test",
            userName: "John Doe",
            userId: "user123",
            requestedAt: Date().addingTimeInterval(-300) // 5 minutes ago
        )
    )
}