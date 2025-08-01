
//  TimePeriodSelector.swift
//  HealthGuide/Views/Shared/TimePeriodSelector.swift
//  Reusable time period selection component with visual feedback
//  Swift 6 compliant with proper state management
import SwiftUI

// MARK: - Time Period Selector
@available(iOS 18.0, *)
struct TimePeriodSelector: View {
    @Binding var selectedPeriods: [TimePeriod]
    let maxSelections: Int
    let showSummary: Bool
    
    init(
        selectedPeriods: Binding<[TimePeriod]>,
        maxSelections: Int,
        showSummary: Bool = true
    ) {
        self._selectedPeriods = selectedPeriods
        self.maxSelections = maxSelections
        self.showSummary = showSummary
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            sectionHeader
            
            periodChipsGrid
            
            if needsMoreSelections {
                selectionPrompt
            }
            
            if showSummary && !selectedPeriods.isEmpty {
                selectedTimesSummary
            }
        }
    }
    
    // MARK: - Components
    
    private var sectionHeader: some View {
        Text(AppStrings.AddItem.timesLabel)
            .font(.monaco(AppTheme.Typography.footnote))
            .foregroundColor(AppTheme.Colors.textSecondary)
    }
    
    private var periodChipsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(TimePeriod.allCases.filter { $0 != .custom }, id: \.self) { period in
                    TimePeriodChip(
                        period: period,
                        isSelected: selectedPeriods.contains(period),
                        isDisabled: !canSelectPeriod(period),
                        action: {
                            togglePeriod(period)
                        }
                    )
                }
            }
            .padding(.horizontal, 1)
        }
    }
    
    private var selectionPrompt: some View {
        Text("Select \(remainingSelections) more time\(remainingSelections == 1 ? "" : "s")")
            .font(.monaco(AppTheme.Typography.caption))
            .foregroundColor(AppTheme.Colors.warningOrange)
            .italic()
    }
    
    private var selectedTimesSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
            Text("Schedule Summary")
                .font(.monaco(AppTheme.Typography.footnote))
                .fontWeight(AppTheme.Typography.medium)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text(formattedSelectedTimes())
                .font(.monaco(AppTheme.Typography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                .fill(AppTheme.Colors.primaryBlue.veryLight())
        )
    }
    
    // MARK: - Computed Properties
    
    private var remainingSelections: Int {
        max(0, maxSelections - selectedPeriods.count)
    }
    
    private var needsMoreSelections: Bool {
        selectedPeriods.count < maxSelections && maxSelections > 0
    }
    
    // MARK: - Helper Methods
    
    private func canSelectPeriod(_ period: TimePeriod) -> Bool {
        selectedPeriods.contains(period) || selectedPeriods.count < maxSelections
    }
    
    private func togglePeriod(_ period: TimePeriod) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let index = selectedPeriods.firstIndex(of: period) {
                selectedPeriods.remove(at: index)
            } else if selectedPeriods.count < maxSelections {
                selectedPeriods.append(period)
                selectedPeriods.sort { $0.sortOrder < $1.sortOrder }
            }
        }
    }
    
    private func formattedSelectedTimes() -> String {
        selectedPeriods
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { period in
                let time = formatTime(for: period)
                return "\(period.displayName) (\(time))"
            }
            .joined(separator: " & ")
    }
    
    private func formatTime(for period: TimePeriod) -> String {
        let (hour, minute) = period.defaultTime
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.timeString
    }
}

// MARK: - Time Period Chip
@available(iOS 18.0, *)
struct TimePeriodChip: View {
    let period: TimePeriod
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xxSmall) {
                Image(systemName: iconForPeriod)
                    .font(.system(size: AppTheme.Typography.footnote))
                
                Text(period.displayName)
                    .font(.monaco(AppTheme.Typography.footnote))
                    .fontWeight(isSelected ? AppTheme.Typography.medium : AppTheme.Typography.regular)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(backgroundColor)
            .overlay(border)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !isSelected)
        .opacity(isDisabled && !isSelected ? 0.5 : 1.0)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .accessibilityLabel("\(period.displayName) time period")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isDisabled && !isSelected ? "Maximum selections reached" : "Tap to toggle selection")
    }
    
    // MARK: - Styling Properties
    
    private var foregroundColor: Color {
        if isSelected {
            return AppTheme.Colors.primaryBlue
        } else if isDisabled {
            return AppTheme.Colors.textSecondary
        } else {
            return AppTheme.Colors.textPrimary
        }
    }
    
    private var backgroundColor: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .fill(isSelected ? AppTheme.Colors.primaryBlue.veryLight() : AppTheme.Colors.backgroundPrimary)
    }
    
    private var border: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .stroke(
                isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.borderLight,
                lineWidth: AppTheme.Dimensions.borderWidth
            )
    }
    
    private var iconForPeriod: String {
        switch period {
        case .breakfast:
            return "sunrise.fill"
        case .lunch:
            return "sun.max.fill"
        case .dinner:
            return "sunset.fill"
        case .bedtime:
            return "moon.fill"
        case .custom:
            return "clock.fill"
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.xxLarge) {
        TimePeriodSelector(
            selectedPeriods: .constant([.breakfast, .dinner]),
            maxSelections: 2
        )
        
        Divider()
        
        TimePeriodSelector(
            selectedPeriods: .constant([.breakfast]),
            maxSelections: 3,
            showSummary: false
        )
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}
