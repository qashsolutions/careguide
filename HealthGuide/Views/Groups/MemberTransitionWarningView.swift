//
//  MemberTransitionWarningView.swift
//  HealthGuide
//
//  Warning screen for members transitioning to admin role
//  Emphasizes complete data loss and fresh start
//

import SwiftUI

@available(iOS 18.0, *)
struct MemberTransitionWarningView: View {
    let currentGroupName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var hasReadWarning = false
    @State private var confirmationText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warning background color
                Color.red.opacity(0.05)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xxLarge) {
                        // Warning icon
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                            .padding(.top, AppTheme.Spacing.xxLarge)
                        
                        // Title
                        Text("Start Your Own Care Group?")
                            .font(.monaco(AppTheme.ElderTypography.title))
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        // Main warning
                        VStack(spacing: AppTheme.Spacing.medium) {
                            Text("⚠️ IMPORTANT WARNING ⚠️")
                                .font(.monaco(AppTheme.ElderTypography.headline))
                                .foregroundColor(.red)
                            
                            Text("You will leave \"\(currentGroupName)\" and lose access to ALL shared data")
                                .font(.monaco(AppTheme.ElderTypography.body))
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                        
                        // What will be lost
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            Text("You will PERMANENTLY lose:")
                                .font(.monaco(AppTheme.ElderTypography.headline))
                                .foregroundColor(AppTheme.Colors.textPrimary)
                            
                            ForEach(dataLossItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 20))
                                    
                                    Text(item)
                                        .font(.monaco(AppTheme.ElderTypography.body))
                                        .foregroundColor(AppTheme.Colors.textPrimary)
                                    
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                        
                        // What you'll get
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                            Text("You will start fresh with:")
                                .font(.monaco(AppTheme.ElderTypography.headline))
                                .foregroundColor(AppTheme.Colors.textPrimary)
                            
                            ForEach(freshStartItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 20))
                                    
                                    Text(item)
                                        .font(.monaco(AppTheme.ElderTypography.body))
                                        .foregroundColor(AppTheme.Colors.textPrimary)
                                    
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                        
                        // Confirmation checkbox
                        HStack {
                            Button(action: { hasReadWarning.toggle() }) {
                                Image(systemName: hasReadWarning ? "checkmark.square.fill" : "square")
                                    .foregroundColor(hasReadWarning ? AppTheme.Colors.primaryBlue : Color.gray)
                                    .font(.system(size: 24))
                            }
                            
                            Text("I understand all data will be permanently lost")
                                .font(.monaco(AppTheme.ElderTypography.body))
                                .foregroundColor(AppTheme.Colors.textPrimary)
                            
                            Spacer()
                        }
                        .padding()
                        
                        // Type to confirm (extra safety)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            Text("Type \"LEAVE\" to confirm:")
                                .font(.monaco(AppTheme.ElderTypography.caption))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            
                            TextField("Type LEAVE here", text: $confirmationText)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal)
                        
                        // Action buttons
                        VStack(spacing: AppTheme.Spacing.medium) {
                            Button(action: {
                                onConfirm()
                                dismiss()
                            }) {
                                Text("Leave & Start New Group")
                                    .font(.monaco(AppTheme.ElderTypography.body))
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                                            .fill(canProceed ? Color.red : Color.gray)
                                    )
                            }
                            .disabled(!canProceed)
                            
                            Button(action: {
                                onCancel()
                                dismiss()
                            }) {
                                Text("Cancel")
                                    .font(.monaco(AppTheme.ElderTypography.body))
                                    .fontWeight(.regular)
                                    .foregroundColor(AppTheme.Colors.primaryBlue)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.xxLarge)
                        .padding(.bottom, AppTheme.Spacing.xxxLarge)
                    }
                    .padding(.horizontal, AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle("Warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
        }
    }
    
    private var canProceed: Bool {
        hasReadWarning && confirmationText.uppercased() == "LEAVE"
    }
    
    private let dataLossItems = [
        "All medications and schedules",
        "All supplements and diet items", 
        "All audio memos (up to 10 recordings)",
        "All documents (PDFs, images)",
        "All contacts and phone numbers",
        "All dose history and tracking",
        "Access to group members' data"
    ]
    
    private let freshStartItems = [
        "Your own personal 14-day trial",
        "Empty group you control as admin",
        "Ability to add up to 2 members",
        "Full write permissions",
        "New invite code to share"
    ]
}

// MARK: - Preview
#Preview {
    MemberTransitionWarningView(
        currentGroupName: "Family Care Group",
        onConfirm: { },
        onCancel: { }
    )
}