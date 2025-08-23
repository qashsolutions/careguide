//
//  GroupDashboardView.swift
//  HealthGuide
//
//  Main dashboard for managing care groups
//  Elder-friendly interface for family medication sharing
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct GroupDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = GroupDashboardViewModel()
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @State private var showCreateGroup = false
    @State private var showJoinGroup = false
    @State private var selectedGroup: CareGroupEntity?
    @State private var hasLoadedData = false
    @AppStorage("activeGroupID") private var activeGroupID: String = ""
    
    // Member management states
    @State private var memberNames: [String: String] = [:]
    @State private var memberAccessStates: [String: Bool] = [:]
    @State private var copiedInviteCode = false
    
    var body: some View {
        NavigationStack {
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
                
                VStack(spacing: 0) {
                    // Show read-only banner at the top if applicable
                    ReadOnlyBanner()
                    
                    contentView
                }
            }
            .navigationTitle(AppStrings.TabBar.groups)
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCreateGroup) {
                InviteCodeView(mode: .create, onSuccess: {
                    // Only refresh when group is actually created
                    Task {
                        hasLoadedData = false  // Force reload after creating
                        await viewModel.loadGroups()
                        hasLoadedData = true
                    }
                })
                .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showJoinGroup) {
                InviteCodeView(mode: .join, onSuccess: {
                    // Only refresh when group is actually joined
                    Task {
                        hasLoadedData = false  // Force reload after joining
                        await viewModel.loadGroups()
                        hasLoadedData = true
                    }
                })
                .environment(\.managedObjectContext, viewContext)
            }
            .alert("Invite Code Copied!", isPresented: $copiedInviteCode) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The invite code has been copied to your clipboard")
            }
            .tint(Color.blue)  // Force iOS blue color for alert buttons
            .task {
                guard !hasLoadedData else {
                    print("🔍 [DEBUG] GroupDashboardView.task - Skipped (already loaded)")
                    return
                }
                print("🔍 [DEBUG] GroupDashboardView.task - Starting (first load)")
                print("🔍 [DEBUG] hasLoadedData: \(hasLoadedData)")
                let startTime = Date()
                
                // Load from Core Data first (for any legacy data)
                await viewModel.loadGroups()
                print("🔍 [DEBUG] After loadGroups - isLoading: \(viewModel.isLoading)")
                
                // Load Firebase group members if we have a Firebase group
                if firebaseGroups.currentGroup != nil {
                    await loadGroupMembers()
                    print("🔍 [DEBUG] After loadGroupMembers")
                }
                
                hasLoadedData = true
                print("🔍 [DEBUG] hasLoadedData set to true")
                print("🔍 [PERF] GroupDashboardView.task - Completed in \(Date().timeIntervalSince(startTime))s")
            }
            .onAppear {
                print("🔍 [PERF] GroupDashboardView appeared")
            }
            .onDisappear {
                print("🔍 [PERF] GroupDashboardView disappeared")
            }
            .refreshable {
                print("🔍 [PERF] GroupDashboardView manual refresh triggered")
                await viewModel.loadGroups()
            }
            // COMMENTED OUT: Old implementation causing 100% CPU usage
            // This was listening to ALL Core Data saves across the entire app
            /*
            .onReceive(NotificationCenter.default.publisher(for: .coreDataDidSave)
                .receive(on: DispatchQueue.main)) { _ in
                Task {
                    await viewModel.loadGroups()
                    
                    // If no active group, set the first one as active
                    if activeGroupID.isEmpty, let firstGroup = viewModel.groups.first {
                        activeGroupID = firstGroup.id?.uuidString ?? ""
                    }
                }
            }
            */
            
            // DISABLED: Even debounced listening can cause energy drain
            // Only load groups on appear and via pull-to-refresh
            /*
            .onReceive(
                NotificationCenter.default.publisher(for: .groupDataDidChange)
                    .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            ) { _ in
                Task {
                    await viewModel.loadGroups()
                    
                    // If no active group, set the first one as active
                    if activeGroupID.isEmpty, let firstGroup = viewModel.groups.first {
                        activeGroupID = firstGroup.id?.uuidString ?? ""
                    }
                }
            }
            */
            // Add pull-to-refresh for immediate manual updates
            .refreshable {
                await viewModel.loadGroups()
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        let _ = print("🔍 [DEBUG] contentView - isLoading: \(viewModel.isLoading), groups.count: \(viewModel.groups.count), hasFirebaseGroup: \(firebaseGroups.currentGroup != nil)")
        if viewModel.isLoading {
            LoadingView(message: AppStrings.Loading.loadingMedications)
        } else if let firebaseGroup = firebaseGroups.currentGroup {
            // Use Firebase group directly if available
            firebaseGroupView(firebaseGroup)
        } else if viewModel.groups.isEmpty {
            emptyStateView
        } else {
            groupsList
        }
    }
    
    private var groupsList: some View {
        VStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.medium) {
                    // Only show the first group (personal group) as active
                    if let group = viewModel.groups.first {
                        ActiveGroupCardView(
                            group: group,
                            memberNames: $memberNames,
                            memberAccessStates: $memberAccessStates,
                            onCopyCode: { copyInviteCode(group.inviteCode ?? "") },
                            onShareCode: { shareInviteCode(group.inviteCode ?? "") },
                            onMemberNameChange: { memberId, newName in
                                updateMemberName(memberId: memberId, newName: newName)
                            },
                            onMemberAccessToggle: { memberId in
                                toggleMemberAccess(memberId: memberId)
                            }
                        )
                    }
                }
                .padding(AppTheme.Spacing.screenPadding)
            }
            
            Spacer()
            
            // Informational text at bottom
            VStack(spacing: AppTheme.Spacing.xSmall) {
                Text("You can add up to two members that will have only view capabilities to help with caregiving tasks.")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.screenPadding)
            .padding(.bottom, AppTheme.Spacing.large)
        }
    }
    
    // Display Firebase group directly when Core Data is empty but Firebase has a group
    private func firebaseGroupView(_ group: FirestoreGroup) -> some View {
        VStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.medium) {
                    // Create a temporary CareGroupEntity-like structure for the ActiveGroupCardView
                    // We'll use Firebase data directly
                    FirebaseGroupCardView(
                        firebaseGroup: group,
                        memberNames: $memberNames,
                        memberAccessStates: $memberAccessStates,
                        onCopyCode: { copyInviteCode(group.inviteCode) },
                        onShareCode: { shareInviteCode(group.inviteCode) },
                        onMemberNameChange: { memberId, newName in
                            updateMemberName(memberId: memberId, newName: newName)
                        },
                        onMemberAccessToggle: { memberId in
                            toggleMemberAccess(memberId: memberId)
                        }
                    )
                }
                .padding(AppTheme.Spacing.screenPadding)
            }
            
            Spacer()
            
            // Informational text at bottom
            VStack(spacing: AppTheme.Spacing.xSmall) {
                Text("You can add up to two members that will have only view capabilities to help with caregiving tasks.")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.Spacing.screenPadding)
            .padding(.bottom, AppTheme.Spacing.large)
        }
    }
    
    private func handleGroupTap(_ group: CareGroupEntity, isActive: Bool) {
        if !isActive {
            // Set as active group
            if let groupID = group.id?.uuidString {
                activeGroupID = groupID
                // Load members for the newly active group
                Task {
                    await loadGroupMembers()
                }
            }
        }
    }
    
    private func copyInviteCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedInviteCode = true
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedInviteCode = false
        }
    }
    
    private func shareInviteCode(_ code: String) {
        let message = "Join my care group with this invite code: \(code)"
        let activityVC = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func updateMemberName(memberId: String, newName: String) {
        guard let group = firebaseGroups.currentGroup else { return }
        
        Task {
            do {
                try await firebaseGroups.updateMemberDisplayName(
                    groupId: group.id,
                    memberId: memberId,
                    displayName: newName
                )
                memberNames[memberId] = newName
            } catch {
                print("Failed to update member name: \(error)")
            }
        }
    }
    
    private func toggleMemberAccess(memberId: String) {
        guard let group = firebaseGroups.currentGroup else { return }
        
        let currentState = memberAccessStates[memberId] ?? true
        
        Task {
            do {
                try await firebaseGroups.toggleMemberAccess(
                    groupId: group.id,
                    memberId: memberId,
                    isEnabled: !currentState
                )
                memberAccessStates[memberId] = !currentState
            } catch {
                print("Failed to toggle member access: \(error)")
            }
        }
    }
    
    private func loadGroupMembers() async {
        print("🔍 [DEBUG] loadGroupMembers - Starting")
        guard let group = firebaseGroups.currentGroup else { 
            print("🔍 [DEBUG] loadGroupMembers - No current group, returning")
            return 
        }
        print("🔍 [DEBUG] loadGroupMembers - Current group: \(group.name)")
        
        do {
            print("🔍 [DEBUG] loadGroupMembers - Fetching members for group: \(group.id)")
            let members = try await firebaseGroups.fetchGroupMembers(groupId: group.id)
            print("🔍 [DEBUG] loadGroupMembers - Fetched \(members.count) members")
            
            // Initialize member states
            for member in members {
                if memberNames[member.userId] == nil {
                    memberNames[member.userId] = member.displayName ?? member.name
                }
                memberAccessStates[member.userId] = member.isAccessEnabled
            }
            print("🔍 [DEBUG] loadGroupMembers - Member states initialized")
        } catch {
            print("❌ [DEBUG] loadGroupMembers - Failed: \(error)")
        }
        print("🔍 [DEBUG] loadGroupMembers - Completed")
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.successGreen.opacity(0.5))
            
            Text("Setting up your care group...")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Creating your personal group with invite code")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            
            Spacer()
        }
        .task {
            // Auto-create group if none exists
            if firebaseGroups.currentGroup == nil {
                do {
                    print("🔍 [DEBUG] No group found, creating personal group")
                    try await firebaseGroups.createPersonalGroup()
                    print("✅ [DEBUG] Personal group created")
                    // Reload after creation
                    await viewModel.loadGroups()
                } catch {
                    print("❌ [DEBUG] Failed to create personal group: \(error)")
                }
            }
        }
    }
    
}

// MARK: - Active Group Card View (Expanded with Member Management)
@available(iOS 18.0, *)
struct ActiveGroupCardView: View {
    let group: CareGroupEntity
    @Binding var memberNames: [String: String]
    @Binding var memberAccessStates: [String: Bool]
    let onCopyCode: () -> Void
    let onShareCode: () -> Void
    let onMemberNameChange: (String, String) -> Void
    let onMemberAccessToggle: (String) -> Void
    
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @State private var groupMembers: [FirestoreMember] = []
    @State private var isLoadingMembers = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            // Group header
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.successGreen)
                
                Text(group.name ?? "Unknown Group")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Text("Active")
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .padding(.horizontal, AppTheme.Spacing.small)
                    .padding(.vertical, AppTheme.Spacing.xxSmall)
                    .background(AppTheme.Colors.successGreen.opacity(0.1))
                    .foregroundColor(AppTheme.Colors.successGreen)
                    .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
            }
            
            Divider()
            
            // Invite Code Section (H2 heading)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Invite Code")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                HStack(spacing: AppTheme.Spacing.medium) {
                    // Code display
                    Text(group.inviteCode ?? "------")
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                    
                    // Copy button
                    Button(action: onCopyCode) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.Colors.backgroundSecondary)
                            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                    }
                    
                    // Share button
                    Button(action: onShareCode) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.Colors.backgroundSecondary)
                            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                    }
                }
            }
            
            Divider()
            
            // Members Section
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Members")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                if isLoadingMembers {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if groupMembers.filter({ $0.userId != firebaseGroups.currentGroup?.createdBy }).isEmpty {
                    // No members yet
                    Text("No members in the group. You can add up to two members that will have only view capabilities to help with caregiving tasks")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .padding(AppTheme.Spacing.medium)
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.Colors.backgroundSecondary.opacity(0.5))
                        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                } else {
                    // Show members (excluding admin)
                    ForEach(groupMembers.filter({ $0.userId != firebaseGroups.currentGroup?.createdBy })) { member in
                        HStack(spacing: AppTheme.Spacing.medium) {
                            // Member name text field
                            TextField("Member Name", text: Binding(
                                get: { memberNames[member.userId] ?? member.displayName ?? member.name },
                                set: { newValue in
                                    let trimmed = String(newValue.prefix(10))
                                    memberNames[member.userId] = trimmed
                                    onMemberNameChange(member.userId, trimmed)
                                }
                            ))
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .textFieldStyle(.roundedBorder)
                            .disabled(!(memberAccessStates[member.userId] ?? true))
                            .opacity((memberAccessStates[member.userId] ?? true) ? 1.0 : 0.5)
                            .frame(maxWidth: 200)
                            
                            Spacer()
                            
                            // Access toggle
                            Toggle("", isOn: Binding(
                                get: { memberAccessStates[member.userId] ?? true },
                                set: { _ in onMemberAccessToggle(member.userId) }
                            ))
                            .labelsHidden()
                            .tint(AppTheme.Colors.successGreen)
                        }
                        .padding(.horizontal, AppTheme.Spacing.small)
                    }
                }
                
                // Member count indicator
                Text("\(groupMembers.filter({ $0.userId != firebaseGroups.currentGroup?.createdBy }).count)/2 members added")
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .task {
            await loadMembers()
        }
    }
    
    private func loadMembers() async {
        guard let group = firebaseGroups.currentGroup else {
            isLoadingMembers = false
            return
        }
        
        do {
            groupMembers = try await firebaseGroups.fetchGroupMembers(groupId: group.id)
            isLoadingMembers = false
        } catch {
            print("Failed to load members: \(error)")
            isLoadingMembers = false
        }
    }
}

// MARK: - Group Card View
@available(iOS 18.0, *)
struct GroupCardView: View {
    let group: CareGroupEntity
    let memberCount: Int
    let isActive: Bool
    let onTap: () -> Void
    
    @State private var showShareView = false
    
    @State private var isAdmin: Bool = false
    
    private func checkIfAdmin() async {
        let deviceID = await DeviceCheckManager.shared.getDeviceIdentifier()
        isAdmin = group.adminUserID?.uuidString == deviceID
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: AppTheme.ElderTypography.headline))
                        .foregroundColor(isActive ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    if isAdmin {
                        HStack(spacing: AppTheme.Spacing.medium) {
                            // Share button with better visual prominence
                            if isActive && group.inviteCode != nil {
                                Button(action: { showShareView = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 18, weight: .medium))
                                        Text("Share")
                                            .font(.monaco(AppTheme.ElderTypography.footnote))
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(AppTheme.Colors.primaryBlue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                                    .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Text("Admin")
                                .font(.monaco(AppTheme.ElderTypography.caption))
                                .padding(.horizontal, AppTheme.Spacing.small)
                                .padding(.vertical, AppTheme.Spacing.xxSmall)
                                .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                                .foregroundColor(AppTheme.Colors.primaryBlue)
                                .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                        }
                    }
                }
                
                Text(group.name ?? "Unknown Group")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(isActive ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                
                if isActive && isAdmin {
                    if let inviteCode = group.inviteCode {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                            HStack(spacing: AppTheme.Spacing.xSmall) {
                                Image(systemName: "ticket.fill")
                                    .font(.system(size: AppTheme.ElderTypography.footnote))
                                Text("Code: \(inviteCode)")
                                    .font(.monaco(AppTheme.ElderTypography.footnote))
                                    .fontWeight(AppTheme.Typography.semibold)
                            }
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                        }
                        .padding(.vertical, AppTheme.Spacing.xSmall)
                    }
                }
                
                HStack {
                    Text("\(memberCount) \(memberCount == 1 ? "member" : "members")")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    if !isActive {
                        Text("Inactive")
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .padding(.horizontal, AppTheme.Spacing.small)
                            .padding(.vertical, AppTheme.Spacing.xxSmall)
                            .background(AppTheme.Colors.textSecondary.opacity(0.1))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                    }
                }
            }
            .padding(AppTheme.Spacing.large)
            .background(isActive ? AppTheme.Colors.backgroundSecondary : AppTheme.Colors.backgroundSecondary.opacity(0.5))
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .stroke(isActive ? Color.clear : AppTheme.Colors.borderLight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .sheet(isPresented: $showShareView) {
            ShareInviteView(group: group)
        }
        .task {
            await checkIfAdmin()
        }
    }
}

// MARK: - Firebase Group Card View
// This view displays Firebase group directly when Core Data is empty
@available(iOS 18.0, *)
struct FirebaseGroupCardView: View {
    let firebaseGroup: FirestoreGroup
    @Binding var memberNames: [String: String]
    @Binding var memberAccessStates: [String: Bool]
    let onCopyCode: () -> Void
    let onShareCode: () -> Void
    let onMemberNameChange: (String, String) -> Void
    let onMemberAccessToggle: (String) -> Void
    
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    @State private var groupMembers: [FirestoreMember] = []
    @State private var isLoadingMembers = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            // Group header - just icons, no name
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.successGreen)
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.Colors.successGreen)
            }
            
            // Invite Code Section (prominently displayed)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Invite Code")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                HStack {
                    Text(firebaseGroup.inviteCode)
                        .font(.monaco(AppTheme.ElderTypography.largeTitle))
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                    
                    Spacer()
                    
                    HStack(spacing: AppTheme.Spacing.small) {
                        Button(action: onCopyCode) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.Colors.primaryBlue)
                        }
                        
                        Button(action: onShareCode) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20))
                                .foregroundColor(AppTheme.Colors.primaryBlue)
                        }
                    }
                }
            }
            
            Divider()
            
            // Members Section
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                Text("Members")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                if !groupMembers.isEmpty {
                    ForEach(groupMembers, id: \.userId) { member in
                        HStack {
                            TextField("Member name", text: Binding(
                                get: { memberNames[member.userId] ?? member.displayName ?? member.name },
                                set: { onMemberNameChange(member.userId, $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .disabled(!firebaseGroups.userHasWritePermission)
                            .onChange(of: memberNames[member.userId] ?? "") { _, newValue in
                                if newValue.count > 10 {
                                    memberNames[member.userId] = String(newValue.prefix(10))
                                }
                            }
                            
                            Toggle("", isOn: Binding(
                                get: { memberAccessStates[member.userId] ?? member.isAccessEnabled },
                                set: { _ in onMemberAccessToggle(member.userId) }
                            ))
                            .disabled(!firebaseGroups.userHasWritePermission)
                        }
                    }
                }
                
                if groupMembers.count < 2 {
                    Text("\(2 - groupMembers.count) slot(s) available")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .task {
            await loadMembers()
        }
    }
    
    private func loadMembers() async {
        do {
            groupMembers = try await firebaseGroups.fetchGroupMembers(groupId: firebaseGroup.id)
            // Initialize member states
            for member in groupMembers {
                if memberNames[member.userId] == nil {
                    memberNames[member.userId] = member.displayName ?? member.name
                }
                memberAccessStates[member.userId] = member.isAccessEnabled
            }
            isLoadingMembers = false
        } catch {
            print("Failed to load members: \(error)")
            isLoadingMembers = false
        }
    }
}

// MARK: - View Model
@available(iOS 18.0, *)
@MainActor
final class GroupDashboardViewModel: ObservableObject {
    @Published var groups: [CareGroupEntity] = []
    @Published var isLoading = true
    @Published var error: AppError?
    
    private let coreDataManager = CoreDataManager.shared
    
    func loadGroups() async {
        print("🔍 [DEBUG] GroupDashboardViewModel.loadGroups - Starting")
        print("🔍 [DEBUG] isLoading before: \(isLoading)")
        let startTime = Date()
        isLoading = true
        print("🔍 [DEBUG] isLoading set to true")
        
        // Since we're @MainActor, we don't need to wrap everything
        let context = PersistenceController.shared.container.viewContext
        let request = CareGroupEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            groups = try context.fetch(request)
            print("🔍 [DEBUG] Groups fetched: \(groups.count) groups")
            print("🔍 [DEBUG] Groups: \(groups.map { $0.name ?? "unnamed" })")
            print("🔍 [PERF] GroupDashboardViewModel.loadGroups - Fetched \(groups.count) groups in \(Date().timeIntervalSince(startTime))s")
        } catch {
            self.error = AppError.coreDataFetchFailed
            print("❌ [DEBUG] Failed to load groups: \(error)")
        }
        
        isLoading = false
        print("🔍 [DEBUG] isLoading set to false")
        print("🔍 [DEBUG] Final groups.isEmpty: \(groups.isEmpty)")
    }
}

// MARK: - Preview
#Preview {
    GroupDashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}