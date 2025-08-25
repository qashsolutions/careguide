//
//  JoinGroupPromptView.swift
//  HealthGuide
//
//  Post-FaceID prompt for new users to join a group or start solo trial
//

import SwiftUI

@available(iOS 18.0, *)
struct JoinGroupPromptView: View {
    @Binding var hasCompletedSetup: Bool
    @Binding var isSecondaryUser: Bool
    
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @StateObject private var firebaseAuth = FirebaseAuthService.shared
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    @State private var inviteCode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isJoining = false
    @State private var showTrialStatus = false
    @State private var joinedGroup: FirestoreGroup?
    
    @FocusState private var isCodeFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warm background
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
                        .frame(height: AppTheme.Spacing.xxLarge)
                    
                    // Icon
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .padding(.bottom, AppTheme.Spacing.medium)
                    
                    // Title
                    VStack(spacing: AppTheme.Spacing.small) {
                        Text("Welcome to CareGuide")
                            .font(.monaco(AppTheme.ElderTypography.title))
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        Text("Join with code or start trial")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppTheme.Spacing.large)
                    }
                    .padding(.bottom, AppTheme.Spacing.medium)
                    
                    // Invite code input
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                        Text("Enter 6-digit invite code")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .padding(.horizontal, AppTheme.Spacing.medium)
                        
                        HStack(spacing: AppTheme.Spacing.small) {
                            ForEach(0..<6, id: \.self) { index in
                                CodeDigitDisplay(
                                    digit: codeDigit(at: index),
                                    isActive: inviteCode.count == index && isCodeFieldFocused
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.large)
                        .onTapGesture {
                            isCodeFieldFocused = true
                        }
                        
                        // Hidden text field for input
                        TextField("", text: $inviteCode)
                            .keyboardType(.default)
                            .textInputAutocapitalization(.characters)
                            .focused($isCodeFieldFocused)
                            .opacity(0)
                            .frame(width: 1, height: 1)
                            .onChange(of: inviteCode) { _, newValue in
                                validateCode(newValue)
                            }
                    }
                    .padding(.bottom, 0) // Removed bottom padding to bring buttons closer
                    
                    // Buttons with minimal spacing
                    VStack(spacing: AppTheme.Spacing.small) {
                        // Continue with Code button
                        Button(action: joinGroup) {
                            if isJoining {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                            } else {
                                Text("Continue with Code")
                                    .font(.monaco(AppTheme.ElderTypography.body))
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                            }
                        }
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                                .fill(inviteCode.count == 6 ? AppTheme.Colors.primaryBlue : Color.gray)
                        )
                        .disabled(inviteCode.count != 6 || isJoining)
                        .padding(.horizontal, AppTheme.Spacing.xxLarge)
                        .padding(.top, AppTheme.Spacing.xSmall) // Small top padding
                        
                        // Start Trial Instead button - larger font and better spacing
                        Button(action: startSoloTrial) {
                            Text("Start Trial Instead")
                                .font(.monaco(AppTheme.ElderTypography.largeBody)) // Increased font size
                                .fontWeight(.medium) // Made slightly bolder
                                .foregroundColor(AppTheme.Colors.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        }
                        .padding(.horizontal, AppTheme.Spacing.xxLarge)
                        .padding(.bottom, AppTheme.Spacing.large) // Add bottom padding to lift it from keyboard
                        .disabled(isJoining)
                    }
                    
                    Spacer(minLength: AppTheme.Spacing.medium) // Minimum spacer to prevent flush with keyboard
                }
            }
            .onAppear {
                // Auto-focus the code field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isCodeFieldFocused = true
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .tint(AppTheme.Colors.primaryBlue)
            .sheet(isPresented: $showTrialStatus) {
                TrialStatusView(
                    group: joinedGroup,
                    onContinue: {
                        completeSetup(asSecondary: true)
                    }
                )
                .environmentObject(subscriptionManager)
                .interactiveDismissDisabled()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func codeDigit(at index: Int) -> String {
        guard index < inviteCode.count else { return "" }
        let stringIndex = inviteCode.index(inviteCode.startIndex, offsetBy: index)
        return String(inviteCode[stringIndex])
    }
    
    private func validateCode(_ code: String) {
        // Allow alphanumeric characters only
        let filtered = code.uppercased().filter { $0.isLetter || $0.isNumber }
        inviteCode = String(filtered.prefix(6))
    }
    
    private func joinGroup() {
        guard inviteCode.count == 6 else { return }
        
        isJoining = true
        
        Task {
            do {
                // Sign in anonymously first - MUST complete before any Firestore operations
                let userId = try await firebaseAuth.signInAnonymously()
                print("✅ Signed in as: \(userId)")
                
                // Small delay to ensure auth propagates
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Now try to join the group (this handles "already member" internally)
                let group = try await firebaseGroups.joinGroup(
                    inviteCode: inviteCode,
                    memberName: UIDevice.current.name
                )
                
                joinedGroup = group
                
                // Check primary user's trial/subscription status
                await checkPrimaryUserStatus(group: group)
                
            } catch {
                // Check if this is an "already member" error
                if error.localizedDescription.contains("already a member") {
                    // Handle already a member case - try to load the group and proceed
                    do {
                        let group = try await firebaseGroups.getGroupByInviteCode(inviteCode)
                        joinedGroup = group
                        firebaseGroups.currentGroup = group
                        
                        await MainActor.run {
                            completeSetup(asSecondary: true)
                        }
                    } catch {
                        await MainActor.run {
                            isJoining = false
                            errorMessage = "Unable to rejoin group. Please try again."
                            showingError = true
                        }
                    }
                } else {
                    await MainActor.run {
                        isJoining = false
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }
    }
    
    private func checkPrimaryUserStatus(group: FirestoreGroup) async {
        // Get primary user's trial/subscription status from group
        if let trialEnd = group.trialEndDate {
            let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
            
            await MainActor.run {
                if daysRemaining > 0 {
                    // Active trial - show trial status
                    showTrialStatus = true
                } else if daysRemaining <= 0 {
                    // Trial expired - show upgrade prompt
                    errorMessage = "The family trial has expired. Please ask the group admin to upgrade."
                    showingError = true
                }
                isJoining = false
            }
        } else {
            // Check if primary has active subscription
            // For now, assume they have access and proceed
            await MainActor.run {
                showTrialStatus = true
                isJoining = false
            }
        }
    }
    
    private func startSoloTrial() {
        Task {
            // Sign in anonymously
            _ = try await firebaseAuth.signInAnonymously()
            
            // Create personal group
            try await firebaseGroups.createPersonalGroup()
            
            // Complete setup as primary user
            await MainActor.run {
                completeSetup(asSecondary: false)
                
                // Trigger trial modal to show after dismissing this view
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: Notification.Name("ShowTrialModal"),
                        object: nil
                    )
                }
            }
        }
    }
    
    private func completeSetup(asSecondary: Bool) {
        hasCompletedSetup = true
        isSecondaryUser = asSecondary
        
        // Force refresh the UI
        NotificationCenter.default.post(name: .firebaseGroupDidChange, object: nil)
    }
}

// MARK: - Code Digit Display
@available(iOS 18.0, *)
struct CodeDigitDisplay: View {
    let digit: String
    let isActive: Bool
    
    var body: some View {
        Text(digit)
            .font(.monaco(AppTheme.Typography.title))
            .fontWeight(.semibold)
            .frame(width: 50, height: 60)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                    .stroke(
                        isActive ? AppTheme.Colors.primaryBlue : Color.gray.opacity(0.3),
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
}

// MARK: - Trial Status View
@available(iOS 18.0, *)
struct TrialStatusView: View {
    let group: FirestoreGroup?
    let onContinue: () -> Void
    
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    
    var daysRemaining: Int {
        guard let trialEnd = group?.trialEndDate else { return 14 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xxLarge) {
                Spacer()
                
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                // Title
                Text("Successfully Joined!")
                    .font(.monaco(AppTheme.ElderTypography.title))
                    .fontWeight(.bold)
                
                // Group info
                VStack(spacing: AppTheme.Spacing.medium) {
                    Text("You've joined")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Text(group?.name ?? "Care Group")
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                }
                
                // Trial status
                VStack(spacing: AppTheme.Spacing.small) {
                    if daysRemaining > 0 {
                        Label("\(daysRemaining) days left in family trial", systemImage: "clock.fill")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.warningOrange)
                    } else {
                        Label("Family trial expired", systemImage: "exclamationmark.triangle.fill")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.errorRed)
                    }
                    
                    Text("You're using the primary member's trial period")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                
                // Role info
                VStack(spacing: AppTheme.Spacing.small) {
                    Label("Joining as Care Viewer", systemImage: "eye.fill")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                    
                    Text("You'll be able to view all care information")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Continue button
                Button(action: {
                    onContinue()
                    dismiss()
                }) {
                    Text("Continue")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                                .fill(AppTheme.Colors.primaryBlue)
                        )
                }
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
                
                Spacer()
                    .frame(height: AppTheme.Spacing.xxxLarge)
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Preview
#Preview {
    JoinGroupPromptView(
        hasCompletedSetup: .constant(false),
        isSecondaryUser: .constant(false)
    )
    .environmentObject(SubscriptionManager.shared)
}