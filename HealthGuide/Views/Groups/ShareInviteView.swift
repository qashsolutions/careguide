//
//  ShareInviteView.swift
//  HealthGuide
//
//  Share group invitations via QR code and invite code
//  Elder-friendly with large text and clear instructions
//

import SwiftUI

@available(iOS 18.0, *)
struct ShareInviteView: View {
    @Environment(\.dismiss) private var dismiss
    let group: CareGroupEntity
    
    @State private var showCopiedToast = false
    @State private var isSharing = false
    @State private var qrCodeImage: UIImage?
    
    private let appStoreURL = "https://apps.apple.com/app/id6749387786"
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xxLarge) {
                        headerSection
                        qrCodeSection
                        inviteCodeSection
                        instructionsSection
                        shareButton
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
                
                if showCopiedToast {
                    copiedToastView
                }
            }
            .navigationTitle("Share Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Text("Invite Family Members")
                .font(.monaco(AppTheme.Typography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text(group.name ?? "")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            if let expiry = group.inviteCodeExpiry, expiry > Date() {
                Text("Code expires \(expiry, style: .relative)")
                    .font(.monaco(AppTheme.Typography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
    }
    
    private var qrCodeSection: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Text("1. Scan QR Code")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            QRCodeView(content: appStoreURL, size: 200)
                .padding(AppTheme.Spacing.medium)
                .background(AppTheme.Colors.backgroundSecondary)
                .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            
            Text("Downloads CareGuide App")
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }
    
    private var inviteCodeSection: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Text("2. Enter Invite Code")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            if let inviteCode = group.inviteCode {
                Button(action: copyInviteCode) {
                    VStack(spacing: AppTheme.Spacing.small) {
                        Text(inviteCode)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                        
                        HStack {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: AppTheme.Typography.footnote))
                            Text("Tap to copy")
                                .font(.monaco(AppTheme.Typography.footnote))
                        }
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(AppTheme.Spacing.large)
                    .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                    .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("How to Join:")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            ForEach(instructions, id: \.number) { instruction in
                HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
                    Text("\(instruction.number).")
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(AppTheme.Typography.bold)
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .frame(width: 30, alignment: .leading)
                    
                    Text(instruction.text)
                        .font(.monaco(AppTheme.Typography.body))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
    
    private var shareButton: some View {
        ShareLink(item: createSimpleShareMessage()) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share Invite Code")
            }
            .font(.monaco(AppTheme.Typography.body))
            .fontWeight(AppTheme.Typography.semibold)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.Dimensions.buttonHeight)
            .background(AppTheme.Colors.primaryBlue)
            .foregroundColor(.white)
            .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
        }
    }
    
    private var copiedToastView: some View {
        VStack {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Copied!")
            }
            .font(.monaco(AppTheme.Typography.body))
            .fontWeight(AppTheme.Typography.semibold)
            .foregroundColor(.white)
            .padding()
            .background(AppTheme.Colors.successGreen)
            .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            .shadow(radius: 10)
            
            Spacer()
        }
        .padding(.top, 100)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: showCopiedToast)
    }
    
    private var instructions: [(number: Int, text: String)] {
        [
            (1, "Scan the QR code to download CareGuide"),
            (2, "Open the app and sign in with Face ID"),
            (3, "Select 'Join Group'"),
            (4, "Enter the invite code: \(group.inviteCode ?? "")")
        ]
    }
    
    private func copyInviteCode() {
        guard let code = group.inviteCode else { return }
        UIPasteboard.general.string = code
        
        withAnimation {
            showCopiedToast = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showCopiedToast = false
            }
        }
    }
    
    private func createSimpleShareMessage() -> String {
        let code = group.inviteCode ?? "N/A"
        let groupName = group.name ?? "Health Group"
        
        return """
        Join '\(groupName)' on CareGuide
        
        Code: \(code)
        
        Download: \(appStoreURL)
        """
    }
}

// MARK: - Preview
#Preview {
    let context = PersistenceController.preview.container.viewContext
    let group = CareGroupEntity(context: context)
    group.name = "Johnson Family"
    group.inviteCode = "ABC123"
    group.inviteCodeExpiry = Date().addingTimeInterval(86400)
    
    return ShareInviteView(group: group)
}