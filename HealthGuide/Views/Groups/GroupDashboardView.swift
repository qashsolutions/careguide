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
    @State private var showCreateGroup = false
    @State private var showJoinGroup = false
    @State private var selectedGroup: CareGroupEntity?
    @AppStorage("activeGroupID") private var activeGroupID: String = ""
    
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
                
                contentView
            }
            .navigationTitle(AppStrings.TabBar.groups)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addGroupButton
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                InviteCodeView(mode: .create)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showJoinGroup) {
                InviteCodeView(mode: .join)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $selectedGroup) { group in
                GroupMemberListView(group: group)
                    .environment(\.managedObjectContext, viewContext)
            }
            .task {
                await viewModel.loadGroups()
            }
            .onAppear {
                Task {
                    await viewModel.loadGroups()
                }
            }
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
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading {
            LoadingView(message: AppStrings.Loading.loadingMedications)
        } else if viewModel.groups.isEmpty {
            emptyStateView
        } else {
            groupsList
        }
    }
    
    private var groupsList: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.medium) {
                ForEach(viewModel.groups) { group in
                    let isActive = group.id?.uuidString == activeGroupID
                    
                    GroupCardView(
                        group: group,
                        memberCount: group.members?.count ?? 0,
                        isActive: isActive,
                        onTap: { handleGroupTap(group, isActive: isActive) }
                    )
                }
            }
            .padding(AppTheme.Spacing.screenPadding)
        }
    }
    
    private func handleGroupTap(_ group: CareGroupEntity, isActive: Bool) {
        if isActive {
            selectedGroup = group
        } else {
            // Set as active group
            if let groupID = group.id?.uuidString {
                activeGroupID = groupID
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.successGreen)
            
            Text("No Care Groups Yet")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Create or join a group to share medication schedules with family")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            VStack(spacing: AppTheme.Spacing.medium) {
                Button(action: { showCreateGroup = true }) {
                    Label("Create Group", systemImage: "plus.circle.fill")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .fontWeight(AppTheme.Typography.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(AppTheme.Colors.primaryBlue)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
                
                Button(action: { showJoinGroup = true }) {
                    Label("Join Group", systemImage: "person.badge.plus")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .fontWeight(AppTheme.Typography.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(AppTheme.Colors.backgroundSecondary)
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Spacer()
        }
    }
    
    private var addGroupButton: some View {
        Menu {
            Button(action: { showCreateGroup = true }) {
                Label("Create Group", systemImage: "plus.circle")
            }
            
            Button(action: { showJoinGroup = true }) {
                Label("Join Group", systemImage: "person.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
                .frame(
                    minWidth: AppTheme.Dimensions.minimumTouchTarget,
                    minHeight: AppTheme.Dimensions.minimumTouchTarget
                )
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
    
    private var isAdmin: Bool {
        group.adminUserID == UserManager.shared.getOrCreateUserID()
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
                        HStack(spacing: AppTheme.Spacing.small) {
                            if isActive && group.inviteCode != nil {
                                Button(action: { showShareView = true }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: AppTheme.ElderTypography.footnote))
                                        .foregroundColor(AppTheme.Colors.primaryBlue)
                                        .frame(width: 36, height: 36)
                                        .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                                        .clipShape(Circle())
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
        isLoading = true
        defer { isLoading = false }
        
        // Since we're @MainActor, we don't need to wrap everything
        let context = PersistenceController.shared.container.viewContext
        let request = CareGroupEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            groups = try context.fetch(request)
        } catch {
            self.error = AppError.coreDataFetchFailed
        }
    }
}

// MARK: - Preview
#Preview {
    GroupDashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}