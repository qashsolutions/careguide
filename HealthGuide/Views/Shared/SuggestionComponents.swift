//
//  SuggestionComponents.swift
//  HealthGuide/Views/Shared/SuggestionComponents.swift
//
//  Reusable suggestion UI components for consistent user experience
//  Swift 6 compliant with proper accessibility support
//

import SwiftUI

// MARK: - Recent Suggestion Row
@available(iOS 18.0, *)
struct RecentSuggestionRow: View {
    let suggestion: String
    let itemType: HealthItemType
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.small) {
                iconView
                
                suggestionText
                
                Spacer()
                
                actionIndicator
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .accessibilityLabel("Use recent entry: \(suggestion)")
        .accessibilityHint("Fills the field with this previously entered value")
    }
    
    // MARK: - Components
    
    private var iconView: some View {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: AppTheme.Typography.footnote))
            .foregroundColor(AppTheme.Colors.textSecondary)
            .frame(width: 16)
    }
    
    private var suggestionText: some View {
        Text(suggestion)
            .font(.monaco(AppTheme.Typography.body))
            .foregroundColor(AppTheme.Colors.textPrimary)
            .lineLimit(1)
    }
    
    private var actionIndicator: some View {
        Image(systemName: "arrow.up.left.circle.fill")
            .font(.system(size: AppTheme.Typography.footnote))
            .foregroundColor(AppTheme.Colors.primaryBlue.opacity(0.6))
    }
}

// MARK: - Suggestion Header
@available(iOS 18.0, *)
struct SuggestionHeader: View {
    let title: String
    let showClearButton: Bool
    let onClear: () -> Void
    
    init(title: String = "Recent", showClearButton: Bool = true, onClear: @escaping () -> Void = {}) {
        self.title = title
        self.showClearButton = showClearButton
        self.onClear = onClear
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.monaco(AppTheme.Typography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            if showClearButton {
                clearButton
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.xSmall)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.5))
    }
    
    private var clearButton: some View {
        Button("Clear", action: onClear)
            .font(.monaco(AppTheme.Typography.caption))
            .foregroundColor(AppTheme.Colors.primaryBlue)
            .accessibilityLabel("Clear recent suggestions")
            .accessibilityHint("Removes all recent entries from the list")
    }
}

// MARK: - Suggestion Container
@available(iOS 18.0, *)
struct SuggestionContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(containerBackground)
        .padding(.top, 4)
    }
    
    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.inputCornerRadius)
            .fill(AppTheme.Colors.backgroundPrimary)
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 8,
                x: 0,
                y: 4
            )
    }
}

// MARK: - Suggestion Divider
@available(iOS 18.0, *)
struct SuggestionDivider: View {
    var body: some View {
        Divider()
            .background(AppTheme.Colors.borderLight)
    }
}

// MARK: - AI Indicator
@available(iOS 18.0, *)
struct AIIndicator: View {
    let text: String
    
    init(text: String = "Smart") {
        self.text = text
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxSmall) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            Text(text)
                .font(.monaco(AppTheme.Typography.caption))
                .foregroundColor(AppTheme.Colors.primaryBlue)
        }
        .accessibilityLabel("AI-powered suggestions available")
        .accessibilityHint("This field provides intelligent suggestions based on your input")
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.large) {
        SuggestionContainer {
            SuggestionHeader(onClear: {})
            
            RecentSuggestionRow(
                suggestion: "Metformin 500mg",
                itemType: .medication,
                onTap: {}
            )
            
            SuggestionDivider()
            
            RecentSuggestionRow(
                suggestion: "Vitamin D",
                itemType: .supplement,
                onTap: {}
            )
        }
        
        AIIndicator()
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}
