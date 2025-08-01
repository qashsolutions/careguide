//
//  GroupMemberListView.swift
//  HealthGuide
//
//  Display group members with permissions
//  Shows read/write access levels for each member
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct GroupMemberListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GroupMemberListViewModel
    
    let group: CareGroupEntity
    
    init(group: CareGroupEntity) {
        self.group = group
        self._viewModel = StateObject(wrappedValue: GroupMemberListViewModel(group: group))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        groupInfoSection
                        
                        membersSection
                        
                        if viewModel.isAdmin {
                            inviteSection
                        }
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle(group.name ?? "Unknown Group")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadMembers()
            }
        }
    }
    
    private var groupInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Image(systemName: "person.3.fill")
                    .font(.system(size: AppTheme.Typography.headline))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                
                Spacer()
                
                if viewModel.isAdmin {
                    Text("Admin")
                        .font(.monaco(AppTheme.Typography.caption))
                        .padding(.horizontal, AppTheme.Spacing.small)
                        .padding(.vertical, AppTheme.Spacing.xxSmall)
                        .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                }
            }
            
            Text("\(viewModel.members.count) \(viewModel.members.count == 1 ? "member" : "members")")
                .font(.monaco(AppTheme.Typography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Members")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            ForEach(viewModel.members) { member in
                MemberRowView(
                    member: member,
                    isCurrentUser: member.userID == viewModel.currentUserID
                )
            }
        }
    }
    
    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Invite Code")
                .font(.monaco(AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.small) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(Array(group.inviteCode ?? ""), id: \.self) { digit in
                        Text(String(digit))
                            .font(.monaco(AppTheme.Typography.title))
                            .fontWeight(AppTheme.Typography.bold)
                            .frame(width: 45, height: 55)
                            .background(AppTheme.Colors.backgroundSecondary)
                            .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
                    }
                }
                
                Text("Share this code with family members to join")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.large)
            .background(AppTheme.Colors.primaryBlue.opacity(0.05))
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        }
    }
}

// MARK: - Member Row View
@available(iOS 18.0, *)
struct MemberRowView: View {
    let member: GroupMemberEntity
    let isCurrentUser: Bool
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Circle()
                .fill(Color(hex: member.profileColor ?? "#007AFF"))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(member.name?.prefix(2).uppercased() ?? "??")
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(AppTheme.Typography.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                HStack {
                    Text(member.name ?? "Unknown Member")
                        .font(.monaco(AppTheme.Typography.body))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.monaco(AppTheme.Typography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                
                Text(member.role ?? "Member")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            PermissionBadge(permission: member.permissions ?? "read")
        }
        .padding(AppTheme.Spacing.medium)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
}

// MARK: - Permission Badge
@available(iOS 18.0, *)
struct PermissionBadge: View {
    let permission: String
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxSmall) {
            Image(systemName: permission == "write" ? "pencil.circle.fill" : "eye.circle.fill")
                .font(.system(size: AppTheme.Typography.footnote))
            
            Text(permission == "write" ? "Write" : "Read")
                .font(.monaco(AppTheme.Typography.caption))
        }
        .foregroundColor(permission == "write" ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary)
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.xxSmall)
        .background(
            (permission == "write" ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary)
                .opacity(0.1)
        )
        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
}

// MARK: - View Model
@available(iOS 18.0, *)
@MainActor
final class GroupMemberListViewModel: ObservableObject {
    @Published var members: [GroupMemberEntity] = []
    let currentUserID = UserDefaults.standard.object(forKey: "currentUserID") as? UUID
    
    let group: CareGroupEntity
    private let coreDataManager = CoreDataManager.shared
    
    init(group: CareGroupEntity) {
        self.group = group
    }
    
    var isAdmin: Bool {
        group.adminUserID == currentUserID
    }
    
    func loadMembers() async {
        if let groupMembers = group.members as? Set<GroupMemberEntity> {
            members = Array(groupMembers).sorted { 
                ($0.name ?? "") < ($1.name ?? "") 
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let context = PersistenceController.preview.container.viewContext
    let group = CareGroupEntity(context: context)
    group.name = "Family Care Group"
    group.inviteCode = "123456"
    
    return GroupMemberListView(group: group)
        .environment(\.managedObjectContext, context)
}