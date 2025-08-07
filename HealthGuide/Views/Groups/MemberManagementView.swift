//
//  MemberManagementView.swift
//  HealthGuide
//
//  View for managing group member roles
//  Only accessible by Super Admin
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct MemberManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let group: CareGroupEntity
    let currentUser: GroupMemberEntity
    
    @State private var showConfirmation = false
    @State private var memberToPromote: GroupMemberEntity?
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "F8F8F8").ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        // Info card
                        infoCard
                        
                        // Current roles
                        currentRolesSection
                        
                        // Member list with role management
                        memberListSection
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle("Manage Roles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
            .alert("Confirm Role Change", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") {
                    if let member = memberToPromote {
                        assignContentAdminRole(to: member)
                    }
                }
            } message: {
                if let member = memberToPromote {
                    Text(getConfirmationMessage(for: member))
                }
            }
            .alert("Role Management", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Label("Role Management", systemImage: "person.3.fill")
                .font(.monaco(AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            Text("As Super Admin, you can designate one member as Content Admin who can edit medications, supplements, and diet plans.")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var currentRolesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Current Roles")
                .font(.monaco(AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.small) {
                // Super Admin (always the current user)
                roleCard(
                    member: currentUser,
                    role: .superAdmin,
                    isCurrentUser: true
                )
                
                // Content Admin (if exists)
                if let contentAdmin = group.contentAdminMember {
                    roleCard(
                        member: contentAdmin,
                        role: .contentAdmin,
                        isCurrentUser: false
                    )
                }
            }
        }
    }
    
    private var memberListSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Assign Content Admin")
                .font(.monaco(AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            if group.regularMembers.isEmpty && group.contentAdminMember == nil {
                emptyStateView
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    // Show current content admin with option to remove
                    if let contentAdmin = group.contentAdminMember {
                        memberRow(
                            member: contentAdmin,
                            currentRole: .contentAdmin,
                            canPromote: false,
                            canDemote: true
                        )
                    }
                    
                    // Show regular members with option to promote
                    ForEach(group.regularMembers, id: \.id) { member in
                        memberRow(
                            member: member,
                            currentRole: .member,
                            canPromote: true,
                            canDemote: false
                        )
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
            
            Text("No other members yet")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text("Invite members to your group to assign roles")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xxLarge)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func roleCard(member: GroupMemberEntity, role: GroupMemberEntity.MemberRole, isCurrentUser: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Profile circle
            Circle()
                .fill(Color(member.profileColor ?? "blue"))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(member.name?.prefix(1).uppercased() ?? "?")
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member.name ?? "Unknown")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.monaco(AppTheme.ElderTypography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                
                Text(member.email ?? "")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Role badge
            HStack(spacing: 4) {
                Image(systemName: role.iconName)
                    .font(.system(size: 16))
                Text(role.displayName)
                    .font(.monaco(AppTheme.ElderTypography.caption))
            }
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, 6)
            .background(role.iconColor)
            .cornerRadius(AppTheme.Dimensions.badgeCornerRadius)
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func memberRow(member: GroupMemberEntity, currentRole: GroupMemberEntity.MemberRole, canPromote: Bool, canDemote: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Profile circle
            Circle()
                .fill(Color(member.profileColor ?? "blue"))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(member.name?.prefix(1).uppercased() ?? "?")
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name ?? "Unknown")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(member.email ?? "")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Action button
            if canPromote {
                Button(action: {
                    memberToPromote = member
                    showConfirmation = true
                }) {
                    Text("Make Admin")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                                .stroke(AppTheme.Colors.primaryBlue, lineWidth: 1)
                        )
                }
            } else if canDemote {
                Button(action: {
                    removeContentAdminRole()
                }) {
                    Text("Remove Admin")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.errorRed)
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                                .stroke(AppTheme.Colors.errorRed, lineWidth: 1)
                        )
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func getConfirmationMessage(for member: GroupMemberEntity) -> String {
        if let currentAdmin = group.contentAdminMember {
            return "\(member.name ?? "This member") will become Content Admin and can edit all group content. \(currentAdmin.name ?? "Current admin") will become a regular member."
        } else {
            return "\(member.name ?? "This member") will become Content Admin and can edit all group content."
        }
    }
    
    private func assignContentAdminRole(to member: GroupMemberEntity) {
        if group.assignContentAdmin(to: member, by: currentUser) {
            do {
                try viewContext.save()
                alertMessage = "\(member.name ?? "Member") is now Content Admin"
                showAlert = true
            } catch {
                alertMessage = "Failed to update role. Please try again."
                showAlert = true
            }
        }
    }
    
    private func removeContentAdminRole() {
        if group.removeContentAdmin(by: currentUser) {
            do {
                try viewContext.save()
                alertMessage = "Content Admin role removed"
                showAlert = true
            } catch {
                alertMessage = "Failed to remove role. Please try again."
                showAlert = true
            }
        }
    }
}