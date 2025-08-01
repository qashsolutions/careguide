//
//  ValidationMessageView.swift
//  HealthGuide
//
//  Inline validation messages with elder-friendly design
//  No modal alerts, clear visual feedback
//

import SwiftUI

@available(iOS 18.0, *)
struct ValidationMessageView: View {
    let message: String
    let type: MessageType
    @State private var isVisible = false
    
    enum MessageType {
        case error
        case warning
        case success
        case info
        
        var color: Color {
            switch self {
            case .error:
                return AppTheme.Colors.errorRed
            case .warning:
                return AppTheme.Colors.warningOrange
            case .success:
                return AppTheme.Colors.successGreen
            case .info:
                return AppTheme.Colors.primaryBlue
            }
        }
        
        var icon: String {
            switch self {
            case .error:
                return "exclamationmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .success:
                return "checkmark.circle.fill"
            case .info:
                return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.xSmall) {
            Image(systemName: type.icon)
                .font(.system(size: AppTheme.Typography.footnote))
                .foregroundColor(type.color)
            
            Text(message)
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(type.color)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
        .onChange(of: message) { _, _ in
            isVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isVisible = true
                }
            }
        }
    }
}

// MARK: - Field Validation View
@available(iOS 18.0, *)
struct FieldValidationView: View {
    let field: String
    let rules: [ValidationRule]
    @Binding var text: String
    
    struct ValidationRule {
        let id = UUID()
        let description: String
        let validate: (String) -> Bool
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
            ForEach(rules, id: \.id) { rule in
                HStack(spacing: AppTheme.Spacing.xSmall) {
                    Image(systemName: rule.validate(text) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: AppTheme.Typography.caption))
                        .foregroundColor(rule.validate(text) ? AppTheme.Colors.successGreen : AppTheme.Colors.borderMedium)
                    
                    Text(rule.description)
                        .font(.monaco(AppTheme.Typography.caption))
                        .foregroundColor(rule.validate(text) ? AppTheme.Colors.textSecondary : AppTheme.Colors.borderMedium)
                        .strikethrough(rule.validate(text))
                }
                .animation(.easeInOut(duration: 0.2), value: rule.validate(text))
            }
        }
        .padding(.top, AppTheme.Spacing.xxSmall)
    }
}

// MARK: - Limit Warning Banner
@available(iOS 18.0, *)
struct LimitWarningBanner: View {
    let message: String
    let action: (() -> Void)?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: AppTheme.Typography.body))
                    .foregroundColor(AppTheme.Colors.warningOrange)
                
                Text(message)
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .lineLimit(isExpanded ? nil : 2)
                
                Spacer()
                
                if message.count > 100 {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: AppTheme.Typography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }
            
            if let action = action {
                HStack {
                    Spacer()
                    Button(AppStrings.Validation.viewTodayButton, action: action)
                        .font(.monaco(AppTheme.Typography.footnote))
                        .fontWeight(AppTheme.Typography.medium)
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .fill(AppTheme.Colors.warningOrange.veryLight())
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .stroke(AppTheme.Colors.warningOrange.light(), lineWidth: AppTheme.Dimensions.borderWidth)
        )
    }
}

// MARK: - Success Confirmation
@available(iOS 18.0, *)
struct SuccessConfirmationView: View {
    let message: String
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: AppTheme.Typography.body))
                    .foregroundColor(AppTheme.Colors.successGreen)
                
                Text(message)
                    .font(.monaco(AppTheme.Typography.body))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(AppTheme.Colors.successGreen.veryLight())
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.large) {
        // Basic validation messages
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            ValidationMessageView(
                message: "Medication name is required",
                type: .error
            )
            
            ValidationMessageView(
                message: AppStrings.Validation.foodSpecificWarning,
                type: .warning
            )
            
            ValidationMessageView(
                message: "Medication added successfully",
                type: .success
            )
            
            ValidationMessageView(
                message: "This medication may interact with your current supplements",
                type: .info
            )
        }
        
        Divider()
        
        // Field validation
        FieldValidationView(
            field: "Password",
            rules: [
                .init(description: "At least 8 characters", validate: { $0.count >= 8 }),
                .init(description: "Contains uppercase letter", validate: { $0.contains(where: { $0.isUppercase }) }),
                .init(description: "Contains number", validate: { $0.contains(where: { $0.isNumber }) })
            ],
            text: .constant("Pass123")
        )
        
        Divider()
        
        // Limit warning
        LimitWarningBanner(
            message: AppStrings.Validation.dailyLimitWarning,
            action: {}
        )
        
        Divider()
        
        // Success confirmation
        SuccessConfirmationView(
            message: "Metformin added to your schedule"
        )
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}