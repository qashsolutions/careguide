//
//  InviteCodeView.swift
//  HealthGuide
//
//  Create or join care groups with 6-digit codes
//  Elder-friendly large input fields and clear instructions
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct InviteCodeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: InviteCodeViewModel
    @FocusState private var isCodeFieldFocused: Bool
    @AppStorage("activeGroupID") private var activeGroupID: String = ""
    @State private var showDeleteConfirmation = false
    @State private var existingGroupToDelete: CareGroup?
    @State private var showJoinSuccessAlert = false
    @State private var joinedGroupName = ""
    
    let mode: GroupMode
    let onSuccess: (() -> Void)?
    
    init(mode: GroupMode, onSuccess: (() -> Void)? = nil) {
        self.mode = mode
        self.onSuccess = onSuccess
        let vm = InviteCodeViewModel(mode: mode)
        vm.onJoinRequestSent = onSuccess
        self._viewModel = StateObject(wrappedValue: vm)
    }
    
    enum GroupMode {
        case create
        case join
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xxLarge) {
                        headerSection
                        
                        if mode == .create {
                            createGroupSection
                        } else {
                            joinGroupSection
                        }
                        
                        actionButton
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle(mode == .create ? "Create Group" : "Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert(AppStrings.Errors.genericTitle, isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .disabled(viewModel.isProcessing)
            .onChange(of: viewModel.groupCreated) { _, created in
                if created {
                    if mode == .join {
                        // Show the read-only alert for members joining
                        joinedGroupName = viewModel.createdGroup?.name ?? "the group"
                        showJoinSuccessAlert = true
                    } else {
                        // Set the new group as active for creators
                        if let groupID = viewModel.createdGroup?.id.uuidString {
                            activeGroupID = groupID
                        }
                        
                        // Call success callback before dismissing
                        onSuccess?()
                        
                        // Dismiss after a short delay to show success
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                            dismiss()
                        }
                    }
                }
            }
            .alert("Welcome to \(joinedGroupName)", isPresented: $showJoinSuccessAlert) {
                Button("Understood") {
                    // Set the group as active
                    if let groupID = viewModel.createdGroup?.id.uuidString {
                        activeGroupID = groupID
                    }
                    
                    // Call success callback and dismiss
                    onSuccess?()
                    dismiss()
                }
            } message: {
                Text("You are joining as a member and will only be able to view the information but not edit.")
            }
            .tint(AppTheme.Colors.primaryBlue)  // Ensure button is visible
            .confirmationDialog(
                "Replace Existing Group?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Current Group", role: .destructive) {
                    Task {
                        await viewModel.deleteExistingGroupAndCreate(existingGroupToDelete)
                    }
                }
                
                Button("Cancel", role: .cancel) {
                    existingGroupToDelete = nil
                }
            } message: {
                Text("You have one valid group. If you create another one, the current group with all members will be deleted.")
            }
            .tint(AppTheme.Colors.primaryBlue)  // Apply tint to the entire dialog
            .onChange(of: viewModel.showExistingGroupWarning) { _, showWarning in
                if showWarning, let group = viewModel.existingAdminGroup {
                    existingGroupToDelete = group
                    showDeleteConfirmation = true
                    viewModel.showExistingGroupWarning = false
                }
            }
            .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
                if shouldDismiss {
                    if let onSuccess = onSuccess {
                        onSuccess()
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: mode == .create ? "person.3.fill" : "person.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            Text(mode == .create ? "Create a group to share medication schedules" : "Enter the 6-digit code to join a group")
                .font(.monaco(AppTheme.Typography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var createGroupSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text(AppStrings.AddItem.nameLabel)
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            TextField("Group name", text: $viewModel.groupName)
                .font(.monaco(AppTheme.Typography.body))
                .padding(AppTheme.Spacing.medium)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                        .stroke(AppTheme.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                )
                .foregroundColor(AppTheme.Colors.textPrimary)  // This sets the text color
                .accentColor(AppTheme.Colors.primaryBlue)  // This sets the cursor color in iOS
                .tint(AppTheme.Colors.primaryBlue)  // Additional cursor color setting for iOS 15+
                .autocorrectionDisabled()
            
            if viewModel.generatedCode.isEmpty {
                Text("A 6-digit code will be generated for others to join")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            } else {
                generatedCodeView
            }
        }
    }
    
    private var joinGroupSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Enter code")
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(0..<6, id: \.self) { index in
                    CodeDigitView(
                        digit: viewModel.codeDigit(at: index),
                        isActive: viewModel.joinCode.count == index && isCodeFieldFocused
                    )
                }
            }
            .onTapGesture {
                isCodeFieldFocused = true
            }
            
            TextField("", text: $viewModel.joinCode)
                .keyboardType(.default)
                .focused($isCodeFieldFocused)
                .opacity(0)
                .frame(width: 1, height: 1)
                .onChange(of: viewModel.joinCode) { _, newValue in
                    viewModel.validateJoinCode(newValue)
                }
        }
    }
    
    private var generatedCodeView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Text("Share this code")
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(Array(viewModel.generatedCode), id: \.self) { digit in
                    Text(String(digit))
                        .font(.monaco(AppTheme.Typography.title))
                        .fontWeight(AppTheme.Typography.bold)
                        .frame(width: 50, height: 60)
                        .background(AppTheme.Colors.backgroundSecondary)
                        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                }
            }
            
        }
    }
    
    private var actionButton: some View {
        Button(action: { Task { await viewModel.processAction() } }) {
            if viewModel.isProcessing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if viewModel.groupCreated {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(mode == .create ? "Group Created!" : "Joined Successfully!")
                }
                .font(.monaco(AppTheme.Typography.body))
                .fontWeight(AppTheme.Typography.semibold)
            } else {
                Text(mode == .create ? "Create Group" : "Join Group")
                    .font(.monaco(AppTheme.Typography.body))
                    .fontWeight(AppTheme.Typography.semibold)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppTheme.Dimensions.buttonHeight)
        .background(viewModel.groupCreated ? AppTheme.Colors.successGreen : 
                   (viewModel.isActionEnabled ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary))
        .foregroundColor(.white)
        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
        .disabled(!viewModel.isActionEnabled || viewModel.isProcessing || viewModel.groupCreated)
    }
}

// MARK: - Code Digit View
@available(iOS 18.0, *)
struct CodeDigitView: View {
    let digit: String
    let isActive: Bool
    
    var body: some View {
        Text(digit)
            .font(.monaco(AppTheme.Typography.title))
            .fontWeight(AppTheme.Typography.semibold)
            .foregroundColor(AppTheme.Colors.textPrimary)
            .frame(width: 50, height: 60)
            .background(AppTheme.Colors.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
                    .stroke(
                        isActive ? AppTheme.Colors.primaryBlue : AppTheme.Colors.borderLight,
                        lineWidth: isActive ? 2 : 1
                    )
            )
            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
}

// MARK: - View Model
@available(iOS 18.0, *)
@MainActor
final class InviteCodeViewModel: ObservableObject {
    @Published var groupName = ""
    @Published var generatedCode = ""
    @Published var joinCode = ""
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var groupCreated = false
    @Published var createdGroup: CareGroup?
    @Published var showExistingGroupWarning = false
    @Published var existingAdminGroup: CareGroup?
    @Published var shouldDismiss = false
    
    let mode: InviteCodeView.GroupMode
    var onJoinRequestSent: (() -> Void)?
    private let coreDataManager = CoreDataManager.shared
    private let firebaseGroups = FirebaseGroupService.shared
    
    init(mode: InviteCodeView.GroupMode) {
        self.mode = mode
    }
    
    var isActionEnabled: Bool {
        switch mode {
        case .create:
            return !groupName.isEmpty
        case .join:
            return joinCode.count == 6
        }
    }
    
    func codeDigit(at index: Int) -> String {
        guard index < joinCode.count else { return "" }
        let stringIndex = joinCode.index(joinCode.startIndex, offsetBy: index)
        return String(joinCode[stringIndex])
    }
    
    func validateJoinCode(_ code: String) {
        // Allow alphanumeric characters only, remove spaces and special characters
        let filtered = code.uppercased().filter { $0.isLetter || $0.isNumber }
        joinCode = String(filtered.prefix(6))
    }
    
    func processAction() async {
        // Prevent multiple group creation
        guard !groupCreated else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            switch mode {
            case .create:
                // Get device ID for group ownership check
                let deviceID = await DeviceCheckManager.shared.getDeviceIdentifier()
                let deviceUUID = UUID(uuidString: deviceID) ?? UUID()
                
                // Check if device already owns a group - admins can only have 1 group
                let existingGroups = try await coreDataManager.fetchGroups()
                let adminGroups = existingGroups.filter { $0.adminUserID == deviceUUID }
                
                if !adminGroups.isEmpty {
                    // User has existing group - show confirmation dialog
                    existingAdminGroup = adminGroups.first
                    showExistingGroupWarning = true
                    return
                }
                
                // No existing group - proceed with creation
                await createNewGroup()
                
            case .join:
                // Get device ID for consistent tracking
                let deviceID = await DeviceCheckManager.shared.getDeviceIdentifier()
                let deviceUUID = UUID(uuidString: deviceID) ?? UUID()
                let memberName = UserDefaults.standard.string(forKey: "userName") ?? "Member"
                
                // Try to join via Firebase (creates join request now)
                do {
                    let status = try await firebaseGroups.joinGroup(
                        inviteCode: joinCode,
                        memberName: memberName
                    )
                    
                    if status == "pending" {
                        print("📨 Join request sent - waiting for admin approval")
                        
                        // Show pending status and trigger dismissal
                        await MainActor.run {
                            self.errorMessage = "Join request sent! You'll be notified when the admin approves."
                            self.showError = true
                        }
                        
                        // Signal to dismiss after showing the message
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.shouldDismiss = true
                            self.onJoinRequestSent?()
                        }
                        
                        return // Don't continue with local group creation
                    }
                    
                    // If we somehow get here with an approved status (shouldn't happen with new flow)
                    print("⚠️ Unexpected: Direct join succeeded (should be pending)")
                    
                } catch {
                    // Firebase join failed, try local only (won't work across Apple IDs)
                    print("⚠️ Firebase join failed: \(error)")
                    
                    // Check if group exists locally (same device only)
                    guard let group = try await coreDataManager.findGroup(byInviteCode: joinCode) else {
                        throw AppError.invalidInviteCode
                    }
                    
                    // Check if group is full (3 member limit)
                    if group.memberCount >= 3 {
                        throw AppError.groupFull(maxMembers: 3)
                    }
                    
                    // Check if user is already in the group
                    if group.members.contains(where: { $0.userID == deviceUUID }) || group.adminUserID == deviceUUID {
                        throw AppError.alreadyInGroup
                    }
                    
                    // Add member locally
                    try await coreDataManager.addMemberToGroup(
                        groupId: group.id,
                        userId: deviceUUID,
                        name: memberName,
                        phone: ""
                    )
                    
                    createdGroup = group
                    groupCreated = true
                    print("⚠️ Joined locally only - won't sync across devices")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func generateInviteCode() -> String {
        String(format: "%06d", Int.random(in: 100000...999999))
    }
    
    func createNewGroup() async {
        print("🔍 DEBUG: createNewGroup called from MainActor context")
        do {
            // Get device ID for local tracking
            let deviceID = await DeviceCheckManager.shared.getDeviceIdentifier()
            let deviceUUID = UUID(uuidString: deviceID) ?? UUID()
            
            // Create new group locally
            let newGroup = CareGroup(
                name: groupName,
                adminUserID: deviceUUID,
                settings: GroupSettings.default
            )
            
            // Save the group locally first - ensure proper actor isolation
            print("🔍 DEBUG: About to call CoreDataManager.saveGroup from MainActor context")
            try await coreDataManager.saveGroup(newGroup)
            print("🔍 DEBUG: CoreDataManager.saveGroup completed successfully")
            
            // Create group in Firebase for cross-Apple ID sharing
            do {
                let firestoreGroup = try await firebaseGroups.createGroup(
                    name: groupName,
                    inviteCode: newGroup.inviteCode
                )
                print("✅ Group created in Firebase with invite code: \(firestoreGroup.inviteCode)")
                
                // Start syncing local medications to Firebase
                await syncLocalDataToFirebase(groupId: firestoreGroup.id)
                
            } catch {
                print("⚠️ Failed to create group in Firebase: \(error)")
                // Group still works locally
            }
            
            // Update state
            generatedCode = newGroup.inviteCode
            createdGroup = newGroup
            groupCreated = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    // Helper function to sync local data to Firebase
    private func syncLocalDataToFirebase(groupId: String) async {
        // This will sync existing medications/supplements to the new Firebase group
        // Implementation depends on your needs
        print("Ready to sync local data to Firebase group: \(groupId)")
    }
    
    func deleteExistingGroupAndCreate(_ existingGroup: CareGroup?) async {
        guard let existingGroup = existingGroup else { return }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // Delete the existing group
            try await coreDataManager.deleteGroup(existingGroup.id)
            
            // Clear the active group ID if it was the deleted group
            if let activeGroupID = UserDefaults.standard.string(forKey: "activeGroupID"),
               activeGroupID == existingGroup.id.uuidString {
                UserDefaults.standard.removeObject(forKey: "activeGroupID")
            }
            
            // Create the new group
            await createNewGroup()
        } catch {
            errorMessage = "Failed to delete existing group: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Preview
#Preview("Create Group") {
    InviteCodeView(mode: .create)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

#Preview("Join Group") {
    InviteCodeView(mode: .join)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
