//
//  EnhancedMemberManagementView.swift
//  HealthGuide
//
//  Enhanced member management for primary users
//  Allows viewing members, editing names, toggling access, and removing members
//

import SwiftUI
import FirebaseFirestore

@available(iOS 18.0, *)
struct EnhancedMemberManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @StateObject private var firebaseAuth = FirebaseAuthService.shared
    
    @State private var groupMembers: [FirestoreMember] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    
    // Edit member name
    @State private var editingMember: FirestoreMember?
    @State private var editedDisplayName = ""
    @State private var showEditSheet = false
    
    // Confirmation dialogs
    @State private var memberToToggle: FirestoreMember?
    @State private var showToggleConfirmation = false
    @State private var memberToRemove: FirestoreMember?
    @State private var showRemoveConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "F8F8F8").ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading members...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groupMembers.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.large) {
                            // Info card
                            infoCard
                            
                            // Members list
                            membersList
                        }
                        .padding(AppTheme.Spacing.screenPadding)
                    }
                }
            }
            .navigationTitle("Manage Members")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
            .task {
                await loadMembers()
            }
            .onReceive(NotificationCenter.default.publisher(for: .firebaseGroupMembersDidChange)) { _ in
                Task {
                    await loadMembers()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .sheet(isPresented: $showEditSheet) {
                if let member = editingMember {
                    EditMemberNameSheet(
                        member: member,
                        displayName: $editedDisplayName,
                        onSave: { newName in
                            await updateMemberDisplayName(member: member, newName: newName)
                        },
                        onCancel: {
                            showEditSheet = false
                            editingMember = nil
                        }
                    )
                }
            }
            .confirmationDialog(
                "Toggle Access",
                isPresented: $showToggleConfirmation,
                presenting: memberToToggle
            ) { member in
                Button(member.isAccessEnabled ? "Disable Access" : "Enable Access") {
                    Task {
                        await toggleMemberAccess(member: member)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { member in
                Text(member.isAccessEnabled 
                    ? "This will prevent \(member.displayName ?? member.name) from accessing group data. They can be re-enabled later."
                    : "This will restore access for \(member.displayName ?? member.name) to view and edit group data.")
            }
            .confirmationDialog(
                "Remove Member", 
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible,  // Make title always visible
                presenting: memberToRemove
            ) { member in
                Button("Remove Member", role: .destructive) {
                    Task {
                        await removeMember(member: member)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { member in
                Text("⚠️ Are you sure you want to permanently remove \(member.displayName ?? member.name) from the group?\n\nThis will:\n• Remove their access to all group data\n• Delete their member status\n• Allow them to rejoin with the invite code\n\nThis action cannot be undone.")
            }
        }
    }
    
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Label("Member Management", systemImage: "person.3.fill")
                .font(.monaco(AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            Text("View and manage group members. You can edit display names, toggle access, or remove members.")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            if let group = firebaseGroups.currentGroup {
                HStack {
                    Text("Group: \(group.name)")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                    Spacer()
                    Text("\(groupMembers.count)/3 members")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                }
                .foregroundColor(AppTheme.Colors.textSecondary)
                .padding(.top, 4)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var membersList: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            ForEach(groupMembers) { member in
                memberCard(for: member)
            }
        }
    }
    
    private func memberCard(for member: FirestoreMember) -> some View {
        let isPrimaryUser = member.userId == firebaseGroups.currentGroup?.createdBy
        let currentUserId = try? firebaseAuth.getCurrentUserIdSync()
        let isCurrentUser = member.userId == currentUserId
        
        return VStack(spacing: 0) {
            // Member info section
            HStack(spacing: AppTheme.Spacing.medium) {
                // Profile circle with initial
                Circle()
                    .fill(member.isAccessEnabled ? Color.blue : Color.gray)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text((member.displayName ?? member.name).prefix(1).uppercased())
                            .font(.monaco(AppTheme.ElderTypography.headline))
                            .foregroundColor(.white)
                    )
                
                // Member details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(member.displayName ?? member.name)
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        if isPrimaryUser {
                            Text("(Primary)")
                                .font(.monaco(AppTheme.ElderTypography.caption))
                                .foregroundColor(AppTheme.Colors.primaryBlue)
                        } else if isCurrentUser {
                            Text("(You)")
                                .font(.monaco(AppTheme.ElderTypography.caption))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        // User ID (truncated)
                        Text("ID: \(String(member.userId.prefix(8)))...")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        // Access status
                        Label(
                            member.isAccessEnabled ? "Active" : "Disabled",
                            systemImage: member.isAccessEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(member.isAccessEnabled ? .green : .red)
                    }
                    
                    // Role badge
                    HStack(spacing: 4) {
                        Image(systemName: member.role == "admin" ? "star.fill" : "person.fill")
                            .font(.system(size: 12))
                        Text(member.role == "admin" ? "Admin" : "Member")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(member.role == "admin" ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary)
                    .cornerRadius(AppTheme.Dimensions.badgeCornerRadius)
                }
                
                Spacer()
            }
            .padding(AppTheme.Spacing.medium)
            
            // Only show actions for non-primary users and if current user is admin
            if !isPrimaryUser && firebaseGroups.userIsAdmin {
                Divider()
                
                // Action buttons
                HStack(spacing: AppTheme.Spacing.small) {
                    // Edit name button
                    Button(action: {
                        editingMember = member
                        editedDisplayName = member.displayName ?? member.name
                        showEditSheet = true
                    }) {
                        Label("Edit Name", systemImage: "pencil")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                    }
                    .buttonStyle(.bordered)
                    
                    // Toggle access button
                    Button(action: {
                        memberToToggle = member
                        showToggleConfirmation = true
                    }) {
                        Label(
                            member.isAccessEnabled ? "Disable" : "Enable",
                            systemImage: member.isAccessEnabled ? "lock.fill" : "lock.open.fill"
                        )
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(member.isAccessEnabled ? .orange : .green)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    // Remove button
                    Button(action: {
                        memberToRemove = member
                        showRemoveConfirmation = true
                    }) {
                        Label("Remove", systemImage: "trash")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.errorRed)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(AppTheme.Spacing.medium)
            }
        }
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
            
            Text("No members yet")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text("Share your group invite code to add members")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Data Operations
    
    private func loadMembers() async {
        guard let group = firebaseGroups.currentGroup else {
            isLoading = false
            return
        }
        
        do {
            groupMembers = try await firebaseGroups.fetchGroupMembers(groupId: group.id)
            
            // Also add the primary user if not in members collection
            if !groupMembers.contains(where: { $0.userId == group.createdBy }) {
                // Create a member entry for the primary user
                var primaryMember = FirestoreMember(
                    id: UUID().uuidString,
                    userId: group.createdBy,
                    groupId: group.id,
                    name: "Primary User",
                    displayName: "Group Creator",
                    role: "admin",
                    permissions: "write",
                    isAccessEnabled: true
                )
                primaryMember.documentId = group.createdBy  // Use userId as documentId for primary
                groupMembers.insert(primaryMember, at: 0)
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
    
    private func updateMemberDisplayName(member: FirestoreMember, newName: String) async {
        guard let group = firebaseGroups.currentGroup else { return }
        
        do {
            try await firebaseGroups.updateMemberDisplayName(
                groupId: group.id,
                memberId: member.userId,
                displayName: newName
            )
            
            // Reload members
            await loadMembers()
            
            showEditSheet = false
            editingMember = nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func toggleMemberAccess(member: FirestoreMember) async {
        guard let group = firebaseGroups.currentGroup else { return }
        
        do {
            try await firebaseGroups.toggleMemberAccess(
                groupId: group.id,
                memberId: member.userId,
                isEnabled: !member.isAccessEnabled
            )
            
            // Reload members
            await loadMembers()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func removeMember(member: FirestoreMember) async {
        guard let group = firebaseGroups.currentGroup else { return }
        
        do {
            try await firebaseGroups.removeMember(
                groupId: group.id,
                memberId: member.userId
            )
            
            // Reload members
            await loadMembers()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Edit Member Name Sheet
@available(iOS 18.0, *)
struct EditMemberNameSheet: View {
    let member: FirestoreMember
    @Binding var displayName: String
    let onSave: (String) async -> Void
    let onCancel: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.large) {
                // Member info
                HStack(spacing: AppTheme.Spacing.medium) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text((member.displayName ?? member.name).prefix(1).uppercased())
                                .font(.monaco(AppTheme.ElderTypography.headline))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading) {
                        Text("Editing Display Name")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        Text("Original: \(member.name)")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(AppTheme.Spacing.medium)
                .background(Color.white)
                .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                
                // Text field
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Display Name")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    TextField("Enter display name", text: $displayName)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            Task {
                                await save()
                            }
                        }
                }
                
                Spacer()
            }
            .padding(AppTheme.Spacing.screenPadding)
            .background(Color(hex: "F8F8F8"))
            .navigationTitle("Edit Member Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(displayName.isEmpty || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.height(300)])
    }
    
    private func save() async {
        guard !displayName.isEmpty else { return }
        
        isSaving = true
        await onSave(displayName)
        isSaving = false
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        EnhancedMemberManagementView()
    }
}