//
//  AddContactView.swift
//  HealthGuide
//
//  Add healthcare provider contacts with device import
//  Elder-friendly interface with duplicate prevention
//

import SwiftUI
import ContactsUI
import CoreData

@available(iOS 18.0, *)
struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var firebaseContacts = FirebaseContactsService.shared
    @StateObject private var groupService = FirebaseGroupService.shared
    
    @State private var name = ""
    @State private var phone = ""
    // Note: ContactEntity doesn't have email field
    @State private var category: ContactEntity.ContactCategory = .doctor
    @State private var specialization = ""
    @State private var address = ""
    @State private var isPrimary = false
    
    @State private var showContactPicker = false
    @State private var showCategoryConfirmation = false
    @State private var importedContact: CNContact?
    @State private var showDuplicateAlert = false
    @State private var duplicateContactName = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, phone, specialization, address
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warm off-white gradient background
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
                        // Import from Contacts Button
                        importContactButton
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                            .padding(.top, AppTheme.Spacing.medium)
                        
                        // Or divider
                        HStack {
                            Rectangle()
                                .fill(AppTheme.Colors.borderLight)
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(.monaco(AppTheme.ElderTypography.footnote))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .padding(.horizontal, AppTheme.Spacing.medium)
                            
                            Rectangle()
                                .fill(AppTheme.Colors.borderLight)
                                .frame(height: 1)
                        }
                        .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        
                        // Manual entry form
                        formContent
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        
                        // Save button
                        saveButton
                            .padding(.horizontal, AppTheme.Spacing.screenPadding)
                            .padding(.bottom, AppTheme.Spacing.xxxLarge)
                    }
                }
            }
            .navigationTitle("Add Healthcare Contact")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView { contact in
                    if let contact = contact {
                        importedContact = contact
                        populateFromContact(contact)
                        showCategoryConfirmation = true
                    }
                }
            }
            .alert("Confirm Contact Type", isPresented: $showCategoryConfirmation) {
                ForEach([ContactEntity.ContactCategory.doctor, .pharmacy, .emergency, .other], id: \.self) { cat in
                    Button(cat.rawValue) {
                        category = cat
                        checkForDuplicate()
                    }
                }
                Button("Cancel", role: .cancel) {
                    clearForm()
                }
            } message: {
                Text("Is \(name) a healthcare provider? Please select the type:")
            }
            .tint(Color.blue)  // Force blue tint for all interactive elements
            .alert("Duplicate Contact", isPresented: $showDuplicateAlert) {
                Button("Replace Existing", role: .destructive) {
                    saveContact(replaceDuplicate: true)
                }
                Button("Cancel", role: .cancel) {
                    clearForm()
                }
            } message: {
                Text("A contact with the phone number \(phone) already exists (\(duplicateContactName)). Do you want to replace it?")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Components
    
    private var importContactButton: some View {
        Button(action: { showContactPicker = true }) {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                    Text("Import from Contacts")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(.semibold)
                    
                    Text("Select from your device contacts")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.large)
            .background(AppTheme.Colors.primaryBlue.opacity(0.1))
            .foregroundColor(AppTheme.Colors.primaryBlue)
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        }
    }
    
    private var formContent: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Category selector
            categorySection
            
            // Name field
            fieldSection(
                label: "Name",
                text: $name,
                placeholder: "Dr. Smith",
                field: .name,
                isRequired: true
            )
            
            // Contact Information Card
            VStack(spacing: AppTheme.Spacing.medium) {
                Text("Contact Information")
                    .font(.monaco(AppTheme.ElderTypography.headline))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Phone number is required")
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Phone field
                fieldSection(
                    label: "Phone",
                    text: $phone,
                    placeholder: "(555) 123-4567",
                    field: .phone,
                    keyboardType: .phonePad
                )
                
                // Note: Email field not available in ContactEntity
            }
            .padding(AppTheme.Spacing.medium)
            .background(AppTheme.Colors.backgroundSecondary)
            .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
            
            // Specialization field
            fieldSection(
                label: "Specialization (Optional)",
                text: $specialization,
                placeholder: "Cardiologist, General Physician, etc.",
                field: .specialization
            )
            
            // Address field
            fieldSection(
                label: "Address (Optional)",
                text: $address,
                placeholder: "123 Medical Center Dr, Suite 100",
                field: .address
            )
            
            // Primary toggle
            primaryToggleSection
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Category")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach([ContactEntity.ContactCategory.doctor, .pharmacy, .emergency, .specialist, .nurse, .therapist, .other], id: \.self) { cat in
                        CategoryButton(
                            category: cat,
                            isSelected: category == cat,
                            action: { category = cat }
                        )
                    }
                }
            }
        }
    }
    
    private func fieldSection(
        label: String,
        text: Binding<String>,
        placeholder: String,
        field: Field,
        keyboardType: UIKeyboardType = .default,
        isRequired: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            HStack {
                Text(label)
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                if isRequired {
                    Text("*")
                        .foregroundColor(AppTheme.Colors.errorRed)
                }
            }
            
            TextField(placeholder, text: text, axis: field == .address ? .vertical : .horizontal)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(keyboardType)
                .focused($focusedField, equals: field)
                .lineLimit(field == .address ? 3 : 1)
        }
    }
    
    private var primaryToggleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text("Primary Contact")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text("Mark as main contact for emergencies")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isPrimary)
                .labelsHidden()
        }
        .padding(AppTheme.Spacing.medium)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
    
    private var saveButton: some View {
        Button(action: { checkForDuplicate() }) {
            Text("Save Contact")
                .font(.monaco(AppTheme.ElderTypography.callout))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Dimensions.elderButtonHeight)
                .background(canSave ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary)
                .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
        }
        .disabled(!canSave)
    }
    
    // MARK: - Computed Properties
    
    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhone = !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return hasName && hasPhone
    }
    
    // MARK: - Actions
    
    private func populateFromContact(_ contact: CNContact) {
        // Name
        let fullName = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        if !fullName.isEmpty {
            name = fullName
        }
        
        // Phone
        if let phoneNumber = contact.phoneNumbers.first {
            phone = phoneNumber.value.stringValue
        }
        
        // Email not available in ContactEntity model
        
        // Try to guess category based on organization
        if !contact.organizationName.isEmpty {
            let organization = contact.organizationName.lowercased()
            if organization.contains("pharmacy") {
                category = .pharmacy
            } else if organization.contains("hospital") ||
                      organization.contains("clinic") ||
                      organization.contains("medical") {
                category = .doctor
            } else if organization.contains("emergency") {
                category = .emergency
            }
        }
        
        // Address
        if let postalAddress = contact.postalAddresses.first {
            let value = postalAddress.value
            address = [value.street, value.city, value.state, value.postalCode]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }
    
    private func checkForDuplicate() {
        guard !phone.isEmpty else {
            saveContact(replaceDuplicate: false)
            return
        }
        
        let request = ContactEntity.fetchRequest()
        request.predicate = NSPredicate(format: "phone == %@", phone)
        
        do {
            let existingContacts = try viewContext.fetch(request)
            if let existing = existingContacts.first {
                duplicateContactName = existing.name ?? "Unknown"
                showDuplicateAlert = true
            } else {
                saveContact(replaceDuplicate: false)
            }
        } catch {
            saveContact(replaceDuplicate: false)
        }
    }
    
    private func saveContact(replaceDuplicate: Bool) {
        do {
            // Delete existing if replacing
            if replaceDuplicate && !phone.isEmpty {
                let request = ContactEntity.fetchRequest()
                request.predicate = NSPredicate(format: "phone == %@", phone)
                let existingContacts = try viewContext.fetch(request)
                existingContacts.forEach { viewContext.delete($0) }
            }
            
            let newContact = ContactEntity(context: viewContext)
            // id is set automatically in awakeFromInsert
            newContact.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            newContact.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            // email field not available in ContactEntity
            newContact.category = category.rawValue
            newContact.isPrimary = isPrimary
            
            // Combine specialization and address in notes field
            var notesContent = ""
            
            if !specialization.isEmpty {
                notesContent = specialization.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if !address.isEmpty {
                let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                if notesContent.isEmpty {
                    notesContent = cleanAddress
                } else {
                    notesContent = "\(notesContent)\n\(cleanAddress)"
                }
            }
            
            newContact.notes = notesContent.isEmpty ? nil : notesContent
            
            try viewContext.save()
            
            // Sync to Firebase if in a group
            if groupService.currentGroup != nil {
                Task {
                    do {
                        try await firebaseContacts.saveContact(
                            name: newContact.name ?? "",
                            category: newContact.category,
                            phone: newContact.phone,
                            isPrimary: newContact.isPrimary,
                            notes: newContact.notes
                        )
                        AppLogger.main.info("✅ Contact synced to Firebase for group sharing")
                    } catch {
                        AppLogger.main.error("⚠️ Failed to sync contact to Firebase: \(error)")
                        // Don't show error - CoreData save succeeded
                    }
                }
            }
            
            dismiss()
        } catch {
            errorMessage = "Failed to save contact. Please try again."
            showErrorAlert = true
        }
    }
    
    private func clearForm() {
        name = ""
        phone = ""
        // email field removed
        specialization = ""
        address = ""
        category = .doctor
        isPrimary = false
        importedContact = nil
    }
}

// MARK: - Category Button
@available(iOS 18.0, *)
struct CategoryButton: View {
    let category: ContactEntity.ContactCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xSmall) {
                Image(systemName: category.iconName)
                    .font(.system(size: 20))
                
                Text(category.rawValue)
                    .font(.monaco(AppTheme.ElderTypography.body))
            }
            .foregroundColor(isSelected ? .white : category.color)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                    .fill(isSelected ? category.color : category.color.opacity(0.1))
            )
        }
        .frame(minHeight: AppTheme.Dimensions.elderButtonHeight)
    }
}

// MARK: - Contact Picker
@available(iOS 18.0, *)
struct ContactPickerView: UIViewControllerRepresentable {
    let onSelection: (CNContact?) -> Void
    
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactOrganizationNameKey,
            CNContactPostalAddressesKey
        ]
        return picker
    }
    
    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelection: (CNContact?) -> Void
        
        init(onSelection: @escaping (CNContact?) -> Void) {
            self.onSelection = onSelection
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelection(contact)
        }
        
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onSelection(nil)
        }
    }
}

// MARK: - Preview
#Preview {
    AddContactView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}