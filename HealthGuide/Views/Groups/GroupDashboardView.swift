//
//  GroupDashboardView.swift
//  HealthGuide
//
//  Main dashboard for managing care groups
//  Elder-friendly interface for family medication sharing
//

import SwiftUI
import CoreData
import FirebaseAuth
import FirebaseFirestore

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
    @State private var groupMembers: [FirestoreMember] = []
    @State private var membersListener: ListenerRegistration?
    @State private var copiedInviteCode = false
    
    // Join group states for existing users
    @State private var joinInviteCode = ""
    @State private var isJoiningGroup = false
    @State private var joinError: String?
    @State private var showJoinError = false
    @FocusState private var isCodeFieldFocused: Bool
    
    // Member transition states
    @State private var showTransitionWarning = false
    @State private var isTransitioning = false
    @State private var isEligibleToCreateGroup = true // Default true, will check async
    @State private var cooldownDaysRemaining = 0
    
    // Waiting for approval state
    @State private var hasPendingRequest = false
    @State private var pendingGroupName: String?
    
    // Member access revocation confirmation
    @State private var showRevokeConfirmation = false
    @State private var memberToRevoke: String?
    
    // Computed properties for dynamic alert
    private var memberIsCurrentlyEnabled: Bool {
        guard let memberId = memberToRevoke else { return true }
        return memberAccessStates[memberId] ?? true
    }
    
    private var accessToggleAlertTitle: String {
        memberIsCurrentlyEnabled ? "Revoke Access" : "Enable Access"
    }
    
    private var accessToggleAlertMessage: String {
        memberIsCurrentlyEnabled 
            ? "Are you sure you want to revoke access?"
            : "Are you sure you want to enable access?"
    }
    
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
            .groupAlerts(
                copiedInviteCode: $copiedInviteCode,
                showJoinError: $showJoinError,
                joinError: joinError,
                showTransitionWarning: $showTransitionWarning,
                showRevokeConfirmation: $showRevokeConfirmation,
                accessToggleAlertTitle: accessToggleAlertTitle,
                accessToggleAlertMessage: accessToggleAlertMessage,
                memberIsCurrentlyEnabled: memberIsCurrentlyEnabled,
                memberToRevoke: $memberToRevoke,
                onTransition: {
                    Task {
                        await viewModel.performMemberToAdminTransition()
                    }
                },
                onCancelTransition: {
                    showTransitionWarning = false
                },
                onPerformAccess: { memberId in
                    performAccessRevocation(memberId: memberId)
                }
            )
            .task {
                guard !hasLoadedData else {
                    print("🔍 [DEBUG] GroupDashboardView.task - Skipped (already loaded)")
                    return
                }
                print("🔍 [DEBUG] GroupDashboardView.task - Starting (first load)")
                print("🔍 [DEBUG] hasLoadedData: \(hasLoadedData)")
                let startTime = Date()
                
                // Check if user has a pending join request
                let (hasPending, groupName) = await firebaseGroups.checkPendingJoinRequest()
                if hasPending {
                    hasPendingRequest = true
                    pendingGroupName = groupName
                    hasLoadedData = true
                    return // Don't load groups if waiting for approval
                }
                
                // Load from Core Data first (for any legacy data)
                await viewModel.loadGroups()
                print("🔍 [DEBUG] After loadGroups - isLoading: \(viewModel.isLoading)")
                
                // Load Firebase group members if we have a Firebase group
                if firebaseGroups.currentGroup != nil {
                    await loadGroupMembers()
                    print("🔍 [DEBUG] After loadGroupMembers")
                    
                    // Check if user is eligible to create a group (for members)
                    if let userId = Auth.auth().currentUser?.uid,
                       let group = firebaseGroups.currentGroup,
                       !group.adminIds.contains(userId) {
                        // User is a member, check their eligibility
                        await checkCreateGroupEligibility()
                    }
                    
                    // Start listening for join requests if admin
                    if firebaseGroups.userIsAdmin {
                        firebaseGroups.startListeningForJoinRequests()
                    }
                }
                
                hasLoadedData = true
                print("🔍 [DEBUG] hasLoadedData set to true")
                print("🔍 [PERF] GroupDashboardView.task - Completed in \(Date().timeIntervalSince(startTime))s")
            }
            .onAppear {
                print("🔍 [PERF] GroupDashboardView appeared")
                
                // Manual access check for members when view appears
                if !firebaseGroups.userIsAdmin {
                    Task {
                        print("🔍 Performing manual access check for member...")
                        await firebaseGroups.manualAccessCheck()
                    }
                }
            }
            .onDisappear {
                print("🔍 [PERF] GroupDashboardView disappeared")
                // Clean up listeners to prevent memory leaks
                membersListener?.remove()
                membersListener = nil
            }
            .refreshable {
                print("🔍 [PERF] GroupDashboardView manual refresh triggered")
                await viewModel.loadGroups()
                
                // Also do manual access check on refresh
                if !firebaseGroups.userIsAdmin {
                    print("🔍 Manual refresh: checking member access...")
                    await firebaseGroups.manualAccessCheck()
                }
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        let _ = print("🔍 [DEBUG] contentView - isLoading: \(viewModel.isLoading), groups.count: \(viewModel.groups.count), hasFirebaseGroup: \(firebaseGroups.currentGroup != nil)")
        if viewModel.isLoading {
            LoadingView(message: AppStrings.Loading.loadingMedications)
        } else if hasPendingRequest, let groupName = pendingGroupName {
            // Show waiting for approval view
            WaitingForApprovalView(groupName: groupName)
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
            
            // Removed old informational text - now shown in MemberListCard
        }
    }
    
    // Display Firebase group directly when Core Data is empty but Firebase has a group
    private func firebaseGroupView(_ group: FirestoreGroup) -> some View {
        let isAdmin = firebaseGroups.userIsAdmin
        let userId = Auth.auth().currentUser?.uid
        
        // Check if user is still a member of this group
        let isStillMember = userId != nil && (group.memberIds.contains(userId!) || group.adminIds.contains(userId!))
        
        // If user is no longer a member, clear the cached group and show empty state
        if !isStillMember {
            // Clear the cached group since user no longer has access
            Task {
                await firebaseGroups.clearCurrentGroup()
            }
            return AnyView(emptyStateView)
        }
        
        return AnyView(VStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.medium) {
                    if isAdmin {
                        // Admin sees full group management
                        FirebaseGroupCardView(
                            firebaseGroup: group,
                            groupMembers: groupMembers,
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
                    } else {
                        // Members see simplified view - just group name
                        VStack(spacing: AppTheme.Spacing.large) {
                            // Group icon and name
                            VStack(spacing: AppTheme.Spacing.medium) {
                                Image(systemName: "person.3.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(AppTheme.Colors.successGreen)
                                
                                Text(group.name)
                                    .font(.monaco(AppTheme.ElderTypography.title))
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                                
                                Text("You are a member of this care group")
                                    .font(.monaco(AppTheme.ElderTypography.caption))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            }
                            .padding(AppTheme.Spacing.xxLarge)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                    }
                }
                .padding(AppTheme.Spacing.screenPadding)
            }
            
            Spacer()
            
            // Bottom section
            VStack(spacing: AppTheme.Spacing.medium) {
                if isAdmin {
                    // Admin sees member management info - now shown in MemberListCard
                    EmptyView()
                } else {
                    // Member sees transition option (only if eligible)
                    if isEligibleToCreateGroup {
                        Button(action: { showTransitionWarning = true }) {
                            Text("Want to start your own care group?")
                                .font(.monaco(AppTheme.ElderTypography.caption))
                                .foregroundColor(AppTheme.Colors.primaryBlue)
                                .underline()
                        }
                        .disabled(isTransitioning)
                    } else {
                        // Show cooldown message
                        VStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.Colors.warningOrange)
                            Text("Group creation available in \(cooldownDaysRemaining) days")
                                .font(.monaco(AppTheme.ElderTypography.caption))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            Text("Members must wait 30 days before creating a group")
                                .font(.monaco(AppTheme.ElderTypography.footnote))
                                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.screenPadding)
            .padding(.bottom, AppTheme.Spacing.large)
        })
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
        // Store the member ID and show confirmation dialog
        memberToRevoke = memberId
        showRevokeConfirmation = true
    }
    
    private func performAccessRevocation(memberId: String) {
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
                memberToRevoke = nil
            } catch {
                print("Failed to toggle member access: \(error)")
            }
        }
    }
    
    private func checkCreateGroupEligibility() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Get user's transition tracking data
            let userDoc = try await Firestore.firestore().collection("users").document(userId).getDocument()
            
            if userDoc.exists, let data = userDoc.data() {
                // Check new cooldown fields that match server rules
                let canCreate = data["canCreateGroup"] as? Bool ?? true
                let cooldownEndDate = (data["cooldownEndDate"] as? Timestamp)?.dateValue()
                let currentRole = data["currentRole"] as? String
                
                if !canCreate {
                    if let cooldownEnd = cooldownEndDate {
                        if Date() < cooldownEnd {
                            // Still in cooldown
                            isEligibleToCreateGroup = false
                            cooldownDaysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: cooldownEnd).day ?? 0
                            AppLogger.main.info("⏳ User in cooldown until: \(cooldownEnd)")
                            AppLogger.main.info("   Days remaining: \(cooldownDaysRemaining)")
                            AppLogger.main.info("   Current role: \(currentRole ?? "unknown")")
                        } else {
                            // Cooldown expired
                            isEligibleToCreateGroup = true
                            cooldownDaysRemaining = 0
                            
                            // Update Firestore to mark cooldown as expired
                            try await Firestore.firestore().collection("users").document(userId).updateData([
                                "canCreateGroup": true,
                                "updatedAt": FieldValue.serverTimestamp()
                            ])
                            AppLogger.main.info("✅ Cooldown expired, user can now create groups")
                        }
                    } else {
                        // No cooldown date but can't create
                        isEligibleToCreateGroup = false
                        cooldownDaysRemaining = 30
                    }
                } else {
                    // Can create group
                    isEligibleToCreateGroup = true
                    cooldownDaysRemaining = 0
                }
                
                // Also check legacy transition count
                let transitionCount = data["transitionCount"] as? Int ?? 0
                if transitionCount >= 3 {
                    isEligibleToCreateGroup = false
                    cooldownDaysRemaining = 999 // Show as permanently restricted
                    AppLogger.main.info("🚫 User has reached maximum transitions")
                }
            } else {
                // No user document = new user, can create group
                isEligibleToCreateGroup = true
                cooldownDaysRemaining = 0
            }
        } catch {
            AppLogger.main.error("Failed to check eligibility: \(error)")
            // Default to eligible on error (will be checked server-side anyway)
            isEligibleToCreateGroup = true
        }
    }
    
    // Swift 6 compliant: Using @MainActor for UI updates
    @MainActor
    private func setupMembersListener() {
        print("🔍 [DEBUG] setupMembersListener - Starting")
        
        // Clean up any existing listener
        membersListener?.remove()
        
        guard let group = firebaseGroups.currentGroup else {
            print("🔍 [DEBUG] setupMembersListener - No current group")
            return
        }
        
        print("🔍 [DEBUG] Setting up real-time listener for members of group: \(group.id)")
        
        // Set up real-time listener for members subcollection
        membersListener = Firestore.firestore()
            .collection("groups")
            .document(group.id)
            .collection("members")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Members listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                // Convert documents to FirestoreMember objects
                let members = snapshot.documents.compactMap { doc -> FirestoreMember? in
                    let data = doc.data()
                    var member = FirestoreMember(
                        id: data["id"] as? String ?? "",
                        userId: data["userId"] as? String ?? "",
                        groupId: data["groupId"] as? String ?? "",
                        name: data["name"] as? String ?? "Unknown",
                        displayName: data["displayName"] as? String,
                        role: data["role"] as? String ?? "member",
                        permissions: data["permissions"] as? String ?? "read",
                        isAccessEnabled: data["isAccessEnabled"] as? Bool ?? true,
                        joinedAt: (data["joinedAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                    member.documentId = doc.documentID
                    return member
                }
                
                Task { @MainActor in
                    self.groupMembers = members
                    
                    // Update member states for UI
                    self.memberNames.removeAll()
                    self.memberAccessStates.removeAll()
                    
                    for member in members {
                        self.memberNames[member.userId] = member.displayName ?? member.name
                        self.memberAccessStates[member.userId] = member.isAccessEnabled
                    }
                    
                    print("📱 Members updated via real-time listener: \(members.count) members")
                }
            }
    }
    
    private func loadGroupMembers() async {
        // Now just sets up the listener instead of one-time fetch
        await MainActor.run {
            setupMembersListener()
        }
    }
    
    // MARK: - Join Group Helpers
    private func joinCodeDigit(at index: Int) -> String {
        guard index < joinInviteCode.count else { return "" }
        let stringIndex = joinInviteCode.index(joinInviteCode.startIndex, offsetBy: index)
        return String(joinInviteCode[stringIndex])
    }
    
    private func validateJoinCode(_ code: String) {
        // Allow alphanumeric characters only
        let filtered = code.uppercased().filter { $0.isLetter || $0.isNumber }
        joinInviteCode = String(filtered.prefix(6))
    }
    
    private func joinGroupWithCode() {
        guard joinInviteCode.count == 6 else { return }
        
        isJoiningGroup = true
        
        Task {
            do {
                // Join the group via Firebase (creates join request)
                let status = try await firebaseGroups.joinGroup(
                    inviteCode: joinInviteCode,
                    memberName: UIDevice.current.name
                )
                
                if status == "pending" {
                    // Show pending message
                    joinError = "Join request sent! Waiting for admin approval."
                    showJoinError = true
                    
                    // Clear the code
                    joinInviteCode = ""
                    isCodeFieldFocused = false
                } else {
                    // Shouldn't happen with new flow
                    hasLoadedData = false
                    await viewModel.loadGroups()
                }
                hasLoadedData = true
                
                isJoiningGroup = false
            } catch {
                isJoiningGroup = false
                joinError = error.localizedDescription
                showJoinError = true
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            // Join a Care Group Card at the top
            VStack(spacing: AppTheme.Spacing.large) {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                    
                    Text("Join a Care Group")
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Have an invite code?")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    HStack(spacing: AppTheme.Spacing.small) {
                        // 6-digit code input boxes
                        ForEach(0..<6, id: \.self) { index in
                            CodeDigitBox(
                                digit: joinCodeDigit(at: index),
                                isActive: joinInviteCode.count == index && isCodeFieldFocused
                            )
                        }
                    }
                    .onTapGesture {
                        isCodeFieldFocused = true
                    }
                    
                    // Hidden text field for input
                    TextField("", text: $joinInviteCode)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.characters)
                        .focused($isCodeFieldFocused)
                        .opacity(0)
                        .frame(width: 1, height: 1)
                        .onChange(of: joinInviteCode) { _, newValue in
                            validateJoinCode(newValue)
                        }
                }
                
                Button(action: joinGroupWithCode) {
                    if isJoiningGroup {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Join Group")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Dimensions.buttonHeight)
                .background(joinInviteCode.count == 6 ? AppTheme.Colors.primaryBlue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                .disabled(joinInviteCode.count != 6 || isJoiningGroup)
            }
            .padding(AppTheme.Spacing.large)
            .background(Color.white)
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .padding(.horizontal, AppTheme.Spacing.screenPadding)
            .padding(.top, AppTheme.Spacing.large)
            
            Text("OR")
                .font(.monaco(AppTheme.ElderTypography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            // Your personal group info
            VStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 50))
                    .foregroundColor(AppTheme.Colors.successGreen.opacity(0.5))
                
                Text("Your Personal Care Group")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            
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

// MARK: - View Model
@available(iOS 18.0, *)
@MainActor
final class GroupDashboardViewModel: ObservableObject {
    @Published var groups: [CareGroupEntity] = []
    @Published var isLoading = true
    @Published var error: AppError?
    
    // Member transition states
    @Published var isTransitioning = false
    @Published var joinError: String?
    @Published var showJoinError = false
    
    private let coreDataManager = CoreDataManager.shared
    private let firebaseGroups = FirebaseGroupService.shared
    
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
    
    // MARK: - Member to Admin Transition
    func performMemberToAdminTransition() async {
        isTransitioning = true
        defer { isTransitioning = false }
        
        guard let userId = Auth.auth().currentUser?.uid,
              let group = firebaseGroups.currentGroup else { return }
        
        do {
            // 1. Check transition eligibility (cooldown and count)
            let canTransition = try await firebaseGroups.checkTransitionEligibility(userId: userId)
            if !canTransition {
                // Show error about cooldown or limit
                joinError = "You must wait 30 days between transitions or have reached the maximum limit."
                showJoinError = true
                return
            }
            
            // 2. Leave current group as member
            try await firebaseGroups.leaveGroupAsMember(groupId: group.id, userId: userId)
            
            // 3. Clear ALL local data (complete wipe)
            await clearAllLocalData()
            
            // 4. Create new personal group as admin with fresh trial
            try await firebaseGroups.createPersonalGroupAsNewAdmin()
            
            // 5. Update transition tracking
            try await firebaseGroups.updateTransitionTracking(userId: userId)
            
            // 6. Reload UI
            await loadGroups()
            
            // 7. Post notification for app-wide refresh
            NotificationCenter.default.post(name: .firebaseGroupDidChange, object: nil)
            
        } catch {
            joinError = error.localizedDescription
            showJoinError = true
        }
    }
    
    private func clearAllLocalData() async {
        // Complete Core Data wipe
        let coreDataManager = CoreDataManager.shared
        
        // Delete all medications
        do {
            let medications = try await coreDataManager.fetchMedications()
            for med in medications {
                try await coreDataManager.deleteMedication(med.id)
            }
        } catch {
            print("Failed to clear medications: \(error)")
        }
        
        // Delete all supplements
        do {
            let supplements = try await coreDataManager.fetchSupplements()
            for supp in supplements {
                try await coreDataManager.deleteSupplement(supp.id)
            }
        } catch {
            print("Failed to clear supplements: \(error)")
        }
        
        // Delete all diet items
        do {
            let diets = try await coreDataManager.fetchDietItems()
            for diet in diets {
                try await coreDataManager.deleteDiet(diet.id)
            }
        } catch {
            print("Failed to clear diets: \(error)")
        }
        
        // Delete all memos
        do {
            let memos = try await coreDataManager.fetchCareMemos()
            for memo in memos {
                try await coreDataManager.deleteCareMemo(memo.id)
            }
        } catch {
            print("Failed to clear memos: \(error)")
        }
        
        // Clear Firebase contacts (contacts are managed in Firebase, not Core Data)
        // They will be cleared when user leaves the group
        // No need to manually delete as they're tied to group membership
        
        // Clear group-related UserDefaults
        UserDefaults.standard.removeObject(forKey: "currentFirebaseGroupId")
        UserDefaults.standard.removeObject(forKey: "activeGroupID")
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
                
                if groupMembers.filter({ $0.userId != firebaseGroups.currentGroup?.createdBy }).isEmpty {
                    // No members yet
                    Text("No members added yet. Share your invite code to add caregivers.")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .padding(AppTheme.Spacing.medium)
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.Colors.backgroundSecondary.opacity(0.5))
                        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                } else {
                    // Show members (excluding admin)
                    ForEach(groupMembers.filter({ $0.userId != firebaseGroups.currentGroup?.createdBy }), id: \.userId) { member in
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

// MARK: - Firebase Group Card View
// This view displays Firebase group directly when Core Data is empty
@available(iOS 18.0, *)
struct FirebaseGroupCardView: View {
    let firebaseGroup: FirestoreGroup
    let groupMembers: [FirestoreMember]  // Now passed in from parent with real-time updates
    @Binding var memberNames: [String: String]
    @Binding var memberAccessStates: [String: Bool]
    let onCopyCode: () -> Void
    let onShareCode: () -> Void
    let onMemberNameChange: (String, String) -> Void
    let onMemberAccessToggle: (String) -> Void
    
    @StateObject private var firebaseGroups = FirebaseGroupService.shared
    
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
                
                // Removed slot count - will show comprehensive text below
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        
        // Comprehensive member info text below the card
        VStack(spacing: AppTheme.Spacing.small) {
            // Count only non-admin members
            let nonAdminMembers = groupMembers.filter { $0.role != "admin" }
            
            if nonAdminMembers.isEmpty {
                Text("You can add up to 2 members to your group.")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            } else if nonAdminMembers.count == 1 {
                Text("1 member added. You can add 1 more.")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Maximum of 2 members reached (3 total including admin).")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
            }
            
            Text("To disable their access to all data, use the toggle button.")
                .font(.monaco(AppTheme.ElderTypography.callout))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppTheme.Spacing.large)
        .padding(.top, AppTheme.Spacing.medium)
    }
    
}

// MARK: - Code Digit Box Component
@available(iOS 18.0, *)
struct CodeDigitBox: View {
    let digit: String
    let isActive: Bool
    
    var body: some View {
        Text(digit)
            .font(.monaco(AppTheme.Typography.title))
            .fontWeight(.semibold)
            .foregroundColor(AppTheme.Colors.textPrimary)
            .frame(width: 45, height: 55)
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

// MARK: - View Modifier for Alerts
private struct GroupAlertsModifier: ViewModifier {
    @Binding var copiedInviteCode: Bool
    @Binding var showJoinError: Bool
    let joinError: String?
    @Binding var showTransitionWarning: Bool
    @Binding var showRevokeConfirmation: Bool
    let accessToggleAlertTitle: String
    let accessToggleAlertMessage: String
    let memberIsCurrentlyEnabled: Bool
    @Binding var memberToRevoke: String?
    let onTransition: () -> Void
    let onCancelTransition: () -> Void
    let onPerformAccess: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .alert("Invite Code Copied!", isPresented: $copiedInviteCode) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The invite code has been copied to your clipboard")
            }
            .tint(.blue)
            .alert("Error", isPresented: $showJoinError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(joinError ?? "Failed to join group")
            }
            .tint(.blue)
            .sheet(isPresented: $showTransitionWarning) {
                MemberTransitionWarningView(
                    currentGroupName: FirebaseGroupService.shared.currentGroup?.name ?? "this group",
                    onConfirm: onTransition,
                    onCancel: onCancelTransition
                )
            }
            .alert(accessToggleAlertTitle, isPresented: $showRevokeConfirmation) {
                Button("Cancel", role: .cancel) { 
                    memberToRevoke = nil
                }
                Button("Yes", role: memberIsCurrentlyEnabled ? .destructive : nil) {
                    if let memberId = memberToRevoke {
                        onPerformAccess(memberId)
                    }
                }
            } message: {
                Text(accessToggleAlertMessage)
            }
            .tint(memberIsCurrentlyEnabled ? .red : .blue)
    }
}

// Extension to use the modifier
extension View {
    func groupAlerts(
        copiedInviteCode: Binding<Bool>,
        showJoinError: Binding<Bool>,
        joinError: String?,
        showTransitionWarning: Binding<Bool>,
        showRevokeConfirmation: Binding<Bool>,
        accessToggleAlertTitle: String,
        accessToggleAlertMessage: String,
        memberIsCurrentlyEnabled: Bool,
        memberToRevoke: Binding<String?>,
        onTransition: @escaping () -> Void,
        onCancelTransition: @escaping () -> Void,
        onPerformAccess: @escaping (String) -> Void
    ) -> some View {
        self.modifier(GroupAlertsModifier(
            copiedInviteCode: copiedInviteCode,
            showJoinError: showJoinError,
            joinError: joinError,
            showTransitionWarning: showTransitionWarning,
            showRevokeConfirmation: showRevokeConfirmation,
            accessToggleAlertTitle: accessToggleAlertTitle,
            accessToggleAlertMessage: accessToggleAlertMessage,
            memberIsCurrentlyEnabled: memberIsCurrentlyEnabled,
            memberToRevoke: memberToRevoke,
            onTransition: onTransition,
            onCancelTransition: onCancelTransition,
            onPerformAccess: onPerformAccess
        ))
    }
}

// MARK: - Preview
#Preview {
    GroupDashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
