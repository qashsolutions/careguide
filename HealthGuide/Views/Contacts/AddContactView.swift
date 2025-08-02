//
//  AddContactView.swift
//  HealthGuide
//
//  Add healthcare provider contacts with device import
//  Elder-friendly interface with large touch targets
//

import SwiftUI
import ContactsUI

@available(iOS 18.0, *)
struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name = ""
    @State private var phone = ""
    // Note: email field removed as it's not in the ContactEntity model
    @State private var category: ContactEntity.ContactCategory = .doctor
    @State private var isPrimary = false
    @State private var notes = ""
    
    @State private var showContactPicker = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, phone, notes
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
            .navigationTitle("Add Contact")
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
                        populateFromContact(contact)
                    }
                }
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
            
            // Phone field
            fieldSection(
                label: "Phone",
                text: $phone,
                placeholder: "(555) 123-4567",
                field: .phone,
                keyboardType: .phonePad,
                isRequired: true
            )
            
            // Email field removed - not in ContactEntity model
            
            // Primary toggle
            primaryToggleSection
            
            // Notes field
            notesSection
        }
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text("Category")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.small) {
                    ForEach(ContactEntity.ContactCategory.allCases, id: \.self) { cat in
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
            
            TextField(placeholder, text: text)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(keyboardType)
                .focused($focusedField, equals: field)
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
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
            Text("Notes (Optional)")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            TextField("Special instructions or information", text: $notes, axis: .vertical)
                .font(.monaco(AppTheme.ElderTypography.body))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
                .focused($focusedField, equals: .notes)
        }
    }
    
    private var saveButton: some View {
        Button(action: saveContact) {
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
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        
        // Email not stored - ContactEntity doesn't have email field
        
        // Try to guess category based on organization
        if !contact.organizationName.isEmpty {
            let organization = contact.organizationName.lowercased()
            if organization.contains("pharmacy") {
                category = .pharmacy
            } else if organization.contains("hospital") ||
                      organization.contains("emergency") {
                category = .emergency
            }
        }
    }
    
    private func saveContact() {
        let newContact = ContactEntity(context: viewContext)
        // id is set automatically in awakeFromInsert
        newContact.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        newContact.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        newContact.category = category.rawValue
        newContact.isPrimary = isPrimary
        newContact.notes = notes.isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Note: id is set automatically in awakeFromInsert
        
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save contact. Please try again."
            showErrorAlert = true
        }
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
            CNContactOrganizationNameKey
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