//
//  ContactsView.swift
//  HealthGuide
//
//  Healthcare provider contacts management
//  Elder-friendly interface for quick access to doctors and pharmacies
//

import SwiftUI
import CoreData

// Use ContactCategory from ContactEntity extension

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
            .navigationTitle(AppStrings.TabBar.contacts)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addContactButton
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .sheet(isPresented: $showAddContact) {
                AddContactView()
                    .environment(\.managedObjectContext, viewContext)
            }
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
                ForEach(ContactEntity.ContactCategory.allCases, id: \.self) { category in
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
            
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.warningOrange)
            
            Text("No Contacts Yet")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Add your healthcare providers for quick access")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Button(action: { showAddContact = true }) {
                Label("Add First Contact", systemImage: "plus.circle.fill")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .fontWeight(AppTheme.Typography.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
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
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxLarge)
    }
    
    private var addContactButton: some View {
        Button(action: { showAddContact = true }) {
            Image(systemName: "plus")
                .font(.system(size: AppTheme.ElderTypography.headline))
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
    let category: ContactEntity.ContactCategory
    let contacts: [ContactEntity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Image(systemName: category.iconName)
                    .font(.system(size: AppTheme.ElderTypography.body))
                    .foregroundColor(category.color)
                
                Text(category.rawValue)
                    .font(.monaco(AppTheme.ElderTypography.headline))
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
                .fill(ContactEntity.ContactCategory(rawValue: contact.category ?? "")?.color.opacity(0.1) ?? Color.gray.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay(
                    Text(contact.name?.prefix(2).uppercased() ?? "??")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(AppTheme.Typography.semibold)
                        .foregroundColor(ContactEntity.ContactCategory(rawValue: contact.category ?? "")?.color ?? .gray)
                )
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text(contact.name ?? "Unknown Contact")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(contact.phone ?? "No phone")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            if contact.isPrimary {
                Image(systemName: "star.fill")
                    .font(.system(size: AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.warningOrange)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: AppTheme.ElderTypography.footnote))
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
