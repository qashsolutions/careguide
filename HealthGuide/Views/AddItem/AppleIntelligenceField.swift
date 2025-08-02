//
//  AppleIntelligenceField.swift
//  HealthGuide/Views/AddItem/AppleIntelligenceField.swift
//
//  Smart text field with Apple Intelligence integration using native iOS suggestions
//  Production-ready with user history and semantic context
//

import SwiftUI

@available(iOS 18.0, *)
struct AppleIntelligenceField: View {
    @Binding var text: String
    let placeholder: String
    let itemType: HealthItemType
    let fieldType: FieldType
    
    @State private var recentSuggestions: [String] = []
    @State private var showRecentSuggestions = false
    @FocusState private var isFocused: Bool
    
    enum FieldType {
        case name
        case dosage
        
        
        var keyboardType: UIKeyboardType {
            switch self {
            case .name:
                return .default
            case .dosage:
                return .numbersAndPunctuation
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enhanced Text Field with Native Intelligence
            HStack(spacing: AppTheme.Spacing.xSmall) {
                intelligentTextField
                
                // AI Indicator removed for App Store compliance
                // if fieldType == .name && text.isEmpty {
                //     aiIndicator
                // }
            }
            .padding(AppTheme.Spacing.medium)
            .background(fieldBackground)
            .overlay(fieldBorder)
            
            // Recent Suggestions (User History)
            // Temporarily disabled to test native iOS autocomplete
            /*
            if showRecentSuggestions && !recentSuggestions.isEmpty {
                recentSuggestionsView
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            */
        }
        .animation(.easeInOut(duration: 0.2), value: showRecentSuggestions)
        .onAppear {
            loadRecentSuggestions()
        }
    }
    
    // MARK: - Text Field Components
    
    /// Native iOS text field with Apple Intelligence integration
    private var intelligentTextField: some View {
        TextField(placeholder, text: $text)
            .font(.monaco(AppTheme.ElderTypography.body))
            .foregroundColor(AppTheme.Colors.textPrimary)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .keyboardType(fieldType.keyboardType)
            .autocorrectionDisabled(false)
            .textInputAutocapitalization(fieldType == .name ? .words : .never)
            .textContentType(contentType)
            #if os(iOS)
            .writingToolsBehavior(.complete)  // iOS 18+ Writing Tools
            #endif
            .onChange(of: isFocused) { _, focused in
                // Disabled to allow native iOS autocomplete
                // handleFocusChange(focused)
                if focused {
                    donateInteraction()
                }
            }
            .onChange(of: text) { _, newValue in
                // Disabled to allow native iOS autocomplete
                // handleTextChange(newValue)
            }
            .onSubmit {
                handleSubmission()
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
    }
    
    /// Visual indicator for Apple Intelligence features
    private var aiIndicator: some View {
        HStack(spacing: AppTheme.Spacing.xxSmall) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            Text("Smart")
                .font(.monaco(AppTheme.ElderTypography.caption))
                .foregroundColor(AppTheme.Colors.primaryBlue)
        }
    }
    
    /// Field background styling
    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
            .fill(AppTheme.Colors.backgroundPrimary)
    }
    
    /// Field border with focus state
    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
            .stroke(
                isFocused ? AppTheme.Colors.borderFocus : AppTheme.Colors.borderLight,
                lineWidth: isFocused ? AppTheme.Dimensions.focusBorderWidth : AppTheme.Dimensions.borderWidth
            )
    }
    
    // MARK: - Recent Suggestions View
    
    /// Display recent user input suggestions
    private var recentSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            suggestionHeader
            
            ForEach(Array(recentSuggestions.prefix(3)), id: \.self) { suggestion in
                RecentSuggestionRow(
                    suggestion: suggestion,
                    itemType: itemType,
                    onTap: {
                        selectSuggestion(suggestion)
                    }
                )
                
                if suggestion != recentSuggestions.prefix(3).last {
                    Divider()
                        .background(AppTheme.Colors.borderLight)
                }
            }
        }
        .background(suggestionBackground)
        .padding(.top, 4)
    }
    
    /// Header for suggestions section
    private var suggestionHeader: some View {
        HStack {
            Text("Recent")
                .font(.monaco(AppTheme.ElderTypography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            Button("Clear") {
                clearRecentSuggestions()
            }
            .font(.monaco(AppTheme.ElderTypography.caption))
            .foregroundColor(AppTheme.Colors.primaryBlue)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.xSmall)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.5))
    }
    
    /// Background styling for suggestions
    private var suggestionBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
            .fill(AppTheme.Colors.backgroundPrimary)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 8,
                x: 0,
                y: 4
            )
    }
    
    // MARK: - Event Handlers
    
    /// Handle focus state changes
    private func handleFocusChange(_ focused: Bool) {
        if focused && !recentSuggestions.isEmpty {
            showRecentSuggestions = true
        } else {
            showRecentSuggestions = false
        }
    }
    
    /// Handle text input changes
    private func handleTextChange(_ newValue: String) {
        // Filter recent suggestions based on input
        if !newValue.isEmpty && fieldType == .name {
            let filtered = recentSuggestions.filter {
                $0.localizedCaseInsensitiveContains(newValue)
            }
            showRecentSuggestions = !filtered.isEmpty && isFocused
        }
    }
    
    /// Handle form submission
    private func handleSubmission() {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveToRecentSuggestions(text)
        }
        showRecentSuggestions = false
    }
    
    /// Select a suggestion from the list
    private func selectSuggestion(_ suggestion: String) {
        text = suggestion
        showRecentSuggestions = false
        isFocused = false
        
        // Save selection for future suggestions
        saveToRecentSuggestions(suggestion)
    }
    
    // MARK: - User History Management
    
    /// Load recent suggestions from user history
    private func loadRecentSuggestions() {
        let key = "recent_\(itemType.rawValue)_\(fieldType)"
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            recentSuggestions = saved
        }
    }
    
    /// Save suggestion to user history
    private func saveToRecentSuggestions(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let key = "recent_\(itemType.rawValue)_\(fieldType)"
        var recent = recentSuggestions
        
        // Remove if already exists to avoid duplicates
        recent.removeAll { $0.lowercased() == trimmed.lowercased() }
        
        // Add to beginning of list
        recent.insert(trimmed, at: 0)
        
        // Keep only recent 10 items
        recent = Array(recent.prefix(10))
        
        recentSuggestions = recent
        UserDefaults.standard.set(recent, forKey: key)
    }
    
    /// Clear all recent suggestions
    private func clearRecentSuggestions() {
        let key = "recent_\(itemType.rawValue)_\(fieldType)"
        UserDefaults.standard.removeObject(forKey: key)
        recentSuggestions = []
        showRecentSuggestions = false
    }
    
    // MARK: - Accessibility
    
    private var accessibilityLabel: String {
        switch fieldType {
        case .name:
            return "\(itemType.rawValue.capitalized) name"
        case .dosage:
            return "\(itemType.rawValue.capitalized) dosage"
        }
    }
    
    private var accessibilityHint: String {
        switch fieldType {
        case .name:
            return "Enter the name of your \(itemType.rawValue). Recent entries will be suggested."
        case .dosage:
            return "Enter the dosage amount, for example 500mg or 1 tablet."
        }
    }
    
    // MARK: - Apple Intelligence Integration
    
    /// Text content type for better keyboard suggestions
    private var contentType: UITextContentType? {
        switch fieldType {
        case .name:
            return .name  // Use .name to enable iOS suggestions
        case .dosage:
            return nil  // No specific content type for dosages
        }
    }
    
    /// Donate interaction for Siri predictions
    private func donateInteraction() {
        let activity = NSUserActivity(activityType: "com.healthguide.addMedication")
        activity.title = "Add \(itemType.displayName)"
        activity.userInfo = ["itemType": itemType.rawValue, "fieldType": String(describing: fieldType)]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.becomeCurrent()
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.xxLarge) {
        AppleIntelligenceField(
            text: .constant(""),
            placeholder: "Start typing medication name...",
            itemType: .medication,
            fieldType: .name
        )
        
        AppleIntelligenceField(
            text: .constant(""),
            placeholder: "Enter dosage amount...",
            itemType: .medication,
            fieldType: .dosage
        )
        
        AppleIntelligenceField(
            text: .constant(""),
            placeholder: "Start typing supplement name...",
            itemType: .supplement,
            fieldType: .name
        )
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}
