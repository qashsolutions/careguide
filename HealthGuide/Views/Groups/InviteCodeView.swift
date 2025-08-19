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
    
    let mode: GroupMode
    let onSuccess: (() -> Void)?
    
    init(mode: GroupMode, onSuccess: (() -> Void)? = nil) {
        self.mode = mode
        self.onSuccess = onSuccess
        self._viewModel = StateObject(wrappedValue: InviteCodeViewModel(mode: mode))
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
                    // Set the new group as active
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
            .onChange(of: viewModel.showExistingGroupWarning) { _, showWarning in
                if showWarning, let group = viewModel.existingAdminGroup {
                    existingGroupToDelete = group
                    showDeleteConfirmation = true
                    viewModel.showExistingGroupWarning = false
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
                .textFieldStyle(RoundedBorderTextFieldStyle())
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
    
    let mode: InviteCodeView.GroupMode
    private let coreDataManager = CoreDataManager.shared
    
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
                let memberName = UserDefaults.standard.string(forKey: "userName") ?? "Member"
                
                // Try to join from cloud first
                do {
                    if let cloudGroup = try await GroupSyncService.shared.joinGroupFromCloud(
                        inviteCode: joinCode,
                        memberId: deviceID,  // Use device ID directly
                        memberName: memberName
                    ) {
                        // Create local group from cloud data
                        var localGroup = CareGroup(
                            id: UUID(uuidString: cloudGroup.id) ?? UUID(),
                            name: cloudGroup.name,
                            adminUserID: UUID(uuidString: cloudGroup.admin_id) ?? UUID(),  // Fix: Convert String to UUID
                            settings: GroupSettings.default
                        )
                        // Preserve the invite code from cloud
                        localGroup.inviteCode = cloudGroup.invite_code
                        
                        // Save locally
                        try await coreDataManager.saveGroup(localGroup)
                        
                        // Add member locally with device ID
                        try await coreDataManager.addMemberToGroup(
                            groupId: localGroup.id,
                            userId: UUID(uuidString: deviceID) ?? UUID(),  // Store device ID as user ID
                            name: memberName,
                            phone: ""
                        )
                        
                        createdGroup = localGroup
                        groupCreated = true
                        print("✅ Joined group from cloud")
                    }
                } catch {
                    // Fallback to local-only join
                    print("⚠️ Cloud join failed, trying local: \(error)")
                    
                    // Verify the group exists locally
                    guard let group = try await coreDataManager.findGroup(byInviteCode: joinCode) else {
                        throw AppError.invalidInviteCode
                    }
                    
                    // Check if group is full (3 member limit)
                    if group.memberCount >= 3 {
                        throw AppError.groupFull(maxMembers: 3)
                    }
                    
                    // Check if user is already in the group (by device ID)
                    let deviceUUID = UUID(uuidString: deviceID) ?? UUID()
                    if group.members.contains(where: { $0.userID == deviceUUID }) || group.adminUserID == deviceUUID {
                        throw AppError.alreadyInGroup
                    }
                    
                    // Add member locally with device ID
                    try await coreDataManager.addMemberToGroup(
                        groupId: group.id,
                        userId: deviceUUID,  // Store device ID as user ID
                        name: memberName,
                        phone: ""
                    )
                    
                    createdGroup = group
                    groupCreated = true
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
        do {
            // Get device ID instead of random UUID
            let deviceID = await DeviceCheckManager.shared.getDeviceIdentifier()
            let deviceUUID = UUID(uuidString: deviceID) ?? UUID()
            
            // Create new group with device ID as admin ID
            let newGroup = CareGroup(
                name: groupName,
                adminUserID: deviceUUID,  // This is now the device ID
                settings: GroupSettings.default
            )
            
            // Save the group locally
            try await coreDataManager.saveGroup(newGroup)
            
            // Sync to cloud
            do {
                try await GroupSyncService.shared.createGroupInCloud(
                    name: groupName,
                    inviteCode: newGroup.inviteCode,
                    adminId: deviceID  // Use device ID directly
                )
                print("✅ Group synced to cloud")
            } catch {
                print("⚠️ Failed to sync group to cloud: \(error)")
                // Continue even if cloud sync fails - local group is created
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
