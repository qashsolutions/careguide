//
//  ContactsView.swift
//  HealthGuide
//
//  Healthcare provider contacts management
//  Elder-friendly interface with modern iOS 18 card layout
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct ContactsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ContactEntity.category, ascending: true),
                         NSSortDescriptor(keyPath: \ContactEntity.name, ascending: true)],
        animation: .default)
    private var coreDataContacts: FetchedResults<ContactEntity>
    
    @State private var showAddContact = false
    @State private var searchText = ""
    @State private var selectedContact: ContactEntity?
    @State private var showNoPermissionAlert = false
    @State private var hasLoadedFirebaseContacts = false
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var groupService = FirebaseGroupService.shared
    @StateObject private var firebaseContacts = FirebaseContactsService.shared
    
    // Computed property to get contacts from appropriate source
    private var contacts: [ContactEntity] {
        // If in a group, use Firebase contacts (converted to ContactEntity for UI compatibility)
        // Otherwise use CoreData contacts
        if groupService.currentGroup != nil {
            // For now, return CoreData contacts until we update AddContactView
            // This prevents breaking the UI while we transition
            return Array(coreDataContacts)
        } else {
            return Array(coreDataContacts)
        }
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
            .sheet(item: $selectedContact) { contact in
                ContactDetailView(contact: contact)
                    .environment(\.managedObjectContext, viewContext)
            }
            // Add pull-to-refresh for manual updates
            .refreshable {
                // Trigger Core Data refresh by changing the fetch request
                // This will automatically reload the contacts
            }
            // Add debounced selective listening for contact changes
            // Only responds to contact-specific changes, not all Core Data saves
            .onReceive(
                NotificationCenter.default.publisher(for: .contactDataDidChange)
                    .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            ) { _ in
                print("🔍 [PERF] ContactsView received contactDataDidChange notification")
                // FetchRequest will automatically update when Core Data changes
                // This is here for future use if we need manual refresh logic
            }
            .task {
                print("🔍 [PERF] ContactsView task started")
                print("🔍 [PERF] ContactsView has \(contacts.count) contacts loaded")
                
                // Only load Firebase contacts once per view lifecycle
                guard !hasLoadedFirebaseContacts else { 
                    print("🔍 [PERF] ContactsView - Firebase contacts already loaded")
                    return 
                }
                
                // Load Firebase contacts if in a group (simple load, no listeners)
                // Using .task instead of .onAppear prevents multiple calls
                if groupService.currentGroup != nil {
                    await firebaseContacts.refreshIfNeeded()
                    hasLoadedFirebaseContacts = true
                }
            }
            .onDisappear {
                print("🔍 [PERF] ContactsView disappeared")
                // Reset the flag so contacts reload when navigating back
                hasLoadedFirebaseContacts = false
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
                ForEach(groupedContacts.sorted(by: { $0.key.sortPriority < $1.key.sortPriority }), id: \.key) { category, contacts in
                    ContactSectionView(
                        category: category,
                        contacts: contacts,
                        onTap: { contact in
                            selectedContact = contact
                        }
                    )
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
            
            Text("No Contacts Added")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Add your doctors, pharmacies, and emergency contacts for quick access")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Button(action: { 
                if !permissionManager.currentUserCanEdit && permissionManager.isInGroup {
                    showNoPermissionAlert = true
                } else {
                    showAddContact = true
                }
            }) {
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
        Button(action: { 
            if !groupService.userHasWritePermission && groupService.currentGroup != nil {
                showNoPermissionAlert = true
            } else {
                showAddContact = true
            }
        }) {
            Image(systemName: "plus")
                .font(.system(size: AppTheme.ElderTypography.headline))
                .foregroundColor(groupService.userHasWritePermission ? AppTheme.Colors.primaryBlue : Color.gray)
                .frame(
                    minWidth: AppTheme.Dimensions.minimumTouchTarget,
                    minHeight: AppTheme.Dimensions.minimumTouchTarget
                )
        }
        .alert("View Only Access", isPresented: $showNoPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Contact your group admin to make changes")
        }
        .tint(AppTheme.Colors.primaryBlue)  // Ensure OK button is visible
    }
    
    private var filteredContacts: [ContactEntity] {
        let startTime = Date()
        let result: [ContactEntity]
        if searchText.isEmpty {
            result = Array(contacts)
        } else {
            result = contacts.filter { contact in
                (contact.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (contact.phone?.contains(searchText) ?? false) ||
                (contact.notes?.localizedCaseInsensitiveContains(searchText) ?? false) || // specialization
                (contact.category?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > 0.01 { // Only log if takes more than 10ms
            print("🔍 [PERF] ContactsView.filteredContacts took \(elapsed)s for \(contacts.count) contacts")
        }
        return result
    }
    
    private var groupedContacts: [ContactEntity.ContactCategory: [ContactEntity]] {
        let startTime = Date()
        let result = Dictionary(grouping: filteredContacts) { contact in
            ContactEntity.ContactCategory(rawValue: contact.category ?? "") ?? .other
        }
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > 0.01 { // Only log if takes more than 10ms
            print("🔍 [PERF] ContactsView.groupedContacts took \(elapsed)s for \(filteredContacts.count) contacts")
        }
        return result
    }
}

// MARK: - Contact Section View
@available(iOS 18.0, *)
struct ContactSectionView: View {
    let category: ContactEntity.ContactCategory
    let contacts: [ContactEntity]
    let onTap: (ContactEntity) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Section Header
            HStack {
                Image(systemName: category.iconName)
                    .font(.system(size: AppTheme.ElderTypography.body))
                    .foregroundColor(category.color)
                
                Text(category.rawValue)
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Text("\(contacts.count)")
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(category.color.opacity(0.1))
                    )
            }
            .padding(.bottom, AppTheme.Spacing.small)
            
            // Contact Cards
            ForEach(contacts) { contact in
                ContactCardView(contact: contact, onTap: { onTap(contact) })
            }
        }
    }
}

// MARK: - Contact Card View (Modern iOS 18 Design)
@available(iOS 18.0, *)
struct ContactCardView: View {
    let contact: ContactEntity
    let onTap: () -> Void
    
    private var initials: String {
        guard let name = contact.name else { return "?" }
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private var categoryColor: Color {
        ContactEntity.ContactCategory(rawValue: contact.category ?? "")?.color ?? .gray
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.medium) {
                // Avatar Circle
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.1))
                        .frame(width: 64, height: 64)
                    
                    Text(initials)
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .fontWeight(.semibold)
                        .foregroundColor(categoryColor)
                }
                
                // Contact Info
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                    HStack {
                        Text(contact.name ?? "Unknown Contact")
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                        
                        if contact.isPrimary {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.Colors.warningOrange)
                        }
                    }
                    
                    if let notes = contact.notes, !notes.isEmpty {
                        // Show only first line (specialization) in card view
                        Text(notes.components(separatedBy: "\n").first ?? notes)
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: AppTheme.Spacing.small) {
                        if let phone = contact.phone, !phone.isEmpty {
                            Label {
                                Text(formatPhoneNumber(phone))
                                    .font(.monaco(AppTheme.ElderTypography.footnote))
                                    .foregroundColor(AppTheme.Colors.textSecondary)
                            } icon: {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(categoryColor)
                            }
                        }
                        
                        // Email not available in ContactEntity
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatPhoneNumber(_ phone: String) -> String {
        // Basic formatting - can be enhanced
        let cleaned = phone.filter { $0.isNumber }
        if cleaned.count == 10 {
            let areaCode = String(cleaned.prefix(3))
            let prefix = String(cleaned.dropFirst(3).prefix(3))
            let lineNumber = String(cleaned.dropFirst(6))
            return "(\(areaCode)) \(prefix)-\(lineNumber)"
        }
        return phone
    }
}

// MARK: - Contact Detail View
@available(iOS 18.0, *)
struct ContactDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let contact: ContactEntity
    @State private var showDeleteAlert = false
    @State private var showEditView = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "F8F8F8"),
                        Color(hex: "FAFAFA")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        // Contact Header
                        contactHeader
                        
                        // Contact Actions
                        actionButtons
                        
                        // Contact Details
                        detailSections
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle("Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Contact", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteContact()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this contact?")
            }
        }
    }
    
    private var contactHeader: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Large Avatar
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Text(initials)
                    .font(.monaco(48))
                    .fontWeight(.semibold)
                    .foregroundColor(categoryColor)
            }
            
            // Name and Category
            VStack(spacing: AppTheme.Spacing.xSmall) {
                HStack {
                    Text(contact.name ?? "Unknown Contact")
                        .font(.monaco(AppTheme.ElderTypography.title))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    if contact.isPrimary {
                        Image(systemName: "star.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.Colors.warningOrange)
                    }
                }
                
                HStack(spacing: AppTheme.Spacing.small) {
                    Image(systemName: category.iconName)
                        .font(.system(size: 16))
                    Text(category.rawValue)
                        .font(.monaco(AppTheme.ElderTypography.body))
                }
                .foregroundColor(categoryColor)
                
                if let notes = contact.notes, !notes.isEmpty {
                    let components = notes.components(separatedBy: "\n")
                    if let specialization = components.first {
                        Text(specialization)
                            .font(.monaco(AppTheme.ElderTypography.body))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.large)
    }
    
    private var actionButtons: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            if let phone = contact.phone, !phone.isEmpty {
                Button(action: { callPhone(phone) }) {
                    Label("Call", systemImage: "phone.fill")
                        .font(.monaco(AppTheme.ElderTypography.callout))
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.Dimensions.elderButtonHeight)
                        .background(AppTheme.Colors.successGreen)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
                }
            }
            
            // Email button removed - email field not available in ContactEntity
        }
    }
    
    private var detailSections: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Phone
            if let phone = contact.phone, !phone.isEmpty {
                detailRow(
                    icon: "phone.fill",
                    label: "Phone",
                    value: formatPhoneNumber(phone),
                    color: categoryColor
                )
            }
            
            // Email detail removed - email field not available in ContactEntity
            
            // Address (extracted from notes if present)
            if let notes = contact.notes, !notes.isEmpty {
                let components = notes.components(separatedBy: "\n")
                if components.count > 1 {
                    // Address is on second line
                    detailRow(
                        icon: "location.fill",
                        label: "Address",
                        value: components[1],
                        color: categoryColor
                    )
                }
            }
            
            // Delete Button
            Button(action: { showDeleteAlert = true }) {
                Text("Delete Contact")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .foregroundColor(AppTheme.Colors.errorRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .background(AppTheme.Colors.errorRed.opacity(0.1))
                    .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            }
            .padding(.top, AppTheme.Spacing.large)
        }
    }
    
    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                
                Text(label)
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Text(value)
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
    
    // Helper properties
    private var category: ContactEntity.ContactCategory {
        ContactEntity.ContactCategory(rawValue: contact.category ?? "") ?? .other
    }
    
    private var categoryColor: Color {
        category.color
    }
    
    private var initials: String {
        contact.initials
    }
    
    private func formatPhoneNumber(_ phone: String) -> String {
        contact.formattedPhone
    }
    
    private func callPhone(_ phone: String) {
        if let url = contact.phoneURL {
            UIApplication.shared.open(url)
        }
    }
    
    // Email function removed - email field not available in ContactEntity
    
    private func deleteContact() {
        viewContext.delete(contact)
        do {
            try viewContext.save()
            dismiss()
        } catch {
            // Handle error
        }
    }
}

// MARK: - Preview
#Preview {
    ContactsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}