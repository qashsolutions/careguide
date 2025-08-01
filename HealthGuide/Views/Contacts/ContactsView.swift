//
//  ContactsView.swift
//  HealthGuide
//
//  Healthcare provider contacts management
//  Elder-friendly interface for quick access to doctors and pharmacies
//

import SwiftUI
import CoreData

// MARK: - Contact Category
@available(iOS 18.0, *)
enum ContactCategory: String, CaseIterable {
    case doctor = "doctor"
    case pharmacy = "pharmacy"
    case emergency = "emergency"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .doctor: return "Doctors"
        case .pharmacy: return "Pharmacies"
        case .emergency: return "Emergency"
        case .other: return "Other"
        }
    }
    
    var iconName: String {
        switch self {
        case .doctor: return "stethoscope"
        case .pharmacy: return "cross.case.fill"
        case .emergency: return "staroflife.fill"
        case .other: return "person.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .doctor: return AppTheme.Colors.primaryBlue
        case .pharmacy: return AppTheme.Colors.successGreen
        case .emergency: return AppTheme.Colors.errorRed
        case .other: return AppTheme.Colors.textSecondary
        }
    }
}

@available(iOS 18.0, *)
struct ContactsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ContactEntity.category, ascending: true),
                         NSSortDescriptor(keyPath: \ContactEntity.name, ascending: true)],
        animation: .default)
    private var contacts: FetchedResults<ContactEntity>
    
    @State private var showAddContact = false
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                contentView
            }
            .navigationTitle(AppStrings.TabBar.contacts)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addContactButton
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if filteredContacts.isEmpty && searchText.isEmpty {
            emptyStateView
        } else if filteredContacts.isEmpty {
            noResultsView
        } else {
            contactsList
        }
    }
    
    private var contactsList: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.medium) {
                ForEach(ContactCategory.allCases, id: \.self) { category in
                    let categoryContacts = filteredContacts.filter { 
                        $0.category == category.rawValue 
                    }
                    
                    if !categoryContacts.isEmpty {
                        ContactSectionView(
                            category: category,
                            contacts: categoryContacts
                        )
                    }
                }
            }
            .padding(AppTheme.Spacing.screenPadding)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text("No Contacts Yet")
                .font(.monaco(AppTheme.Typography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Add your healthcare providers for quick access")
                .font(.monaco(AppTheme.Typography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Button(action: { showAddContact = true }) {
                Label("Add First Contact", systemImage: "plus.circle.fill")
                    .font(.monaco(AppTheme.Typography.body))
                    .fontWeight(AppTheme.Typography.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.buttonHeight)
                    .background(AppTheme.Colors.primaryBlue)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            }
            .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text("No contacts found")
                .font(.monaco(AppTheme.Typography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxLarge)
    }
    
    private var addContactButton: some View {
        Button(action: { showAddContact = true }) {
            Image(systemName: "plus")
                .font(.system(size: AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
                .frame(
                    minWidth: AppTheme.Dimensions.minimumTouchTarget,
                    minHeight: AppTheme.Dimensions.minimumTouchTarget
                )
        }
    }
    
    private var filteredContacts: [ContactEntity] {
        if searchText.isEmpty {
            return Array(contacts)
        } else {
            return contacts.filter { contact in
                (contact.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (contact.phone?.contains(searchText) ?? false) ||
                (contact.category?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
}

// MARK: - Contact Section View
@available(iOS 18.0, *)
struct ContactSectionView: View {
    let category: ContactCategory
    let contacts: [ContactEntity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Image(systemName: category.iconName)
                    .font(.system(size: AppTheme.Typography.body))
                    .foregroundColor(category.color)
                
                Text(category.displayName)
                    .font(.monaco(AppTheme.Typography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            
            ForEach(contacts) { contact in
                ContactCardView(contact: contact)
            }
        }
    }
}

// MARK: - Contact Card View
@available(iOS 18.0, *)
struct ContactCardView: View {
    let contact: ContactEntity
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Circle()
                .fill(ContactCategory(rawValue: contact.category ?? "")?.color.opacity(0.1) ?? Color.gray.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(contact.name?.prefix(2).uppercased() ?? "??")
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(AppTheme.Typography.semibold)
                        .foregroundColor(ContactCategory(rawValue: contact.category ?? "")?.color ?? .gray)
                )
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text(contact.name ?? "Unknown Contact")
                    .font(.monaco(AppTheme.Typography.body))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(contact.phone ?? "No phone")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            if contact.isPrimary {
                Image(systemName: "star.fill")
                    .font(.system(size: AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.warningOrange)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.medium)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
}

// MARK: - Preview
#Preview {
    ContactsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
