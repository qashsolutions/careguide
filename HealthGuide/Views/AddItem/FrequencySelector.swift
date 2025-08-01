//
//  FrequencySelector.swift
//  HealthGuide/Views/AddItem/FrequencySelector.swift
//
//  Frequency selection with automatic time period management
//  Swift 6 compliant and App Store ready
//

import SwiftUI

@available(iOS 18.0, *)
struct FrequencySelector: View {
    @Binding var selectedFrequency: Schedule.Frequency
    @Binding var selectedPeriods: [TimePeriod]
    let itemType: HealthItemType
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            frequencyButtons
            
            if selectedFrequency.count > 0 {
                TimePeriodSelector(
                    selectedPeriods: $selectedPeriods,
                    maxSelections: selectedFrequency.count
                )
            }
        }
    }
    
    // MARK: - Frequency Buttons
    
    private var frequencyButtons: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(Schedule.Frequency.allCases, id: \.self) { frequency in
                FrequencyButton(
                    frequency: frequency,
                    isSelected: selectedFrequency == frequency,
                    action: {
                        selectFrequency(frequency)
                    }
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func selectFrequency(_ frequency: Schedule.Frequency) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedFrequency = frequency
            adjustSelectedPeriods(for: frequency)
        }
    }
    
    private func adjustSelectedPeriods(for frequency: Schedule.Frequency) {
        let targetCount = frequency.count
        
        if selectedPeriods.count > targetCount {
            selectedPeriods = Array(selectedPeriods.prefix(targetCount))
        } else if selectedPeriods.isEmpty && targetCount > 0 {
            selectedPeriods = defaultPeriods(for: frequency)
        }
    }
    
    private func defaultPeriods(for frequency: Schedule.Frequency) -> [TimePeriod] {
        switch frequency {
        case .once:
            return [.breakfast]
        case .twice:
            return [.breakfast, .dinner]
        case .threeTimesDaily:
            return [.breakfast, .lunch, .dinner]
        }
    }
}

// MARK: - Frequency Button
@available(iOS 18.0, *)
struct FrequencyButton: View {
    let frequency: Schedule.Frequency
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xxSmall) {
                Text(frequency.displayName)
                    .font(.monaco(AppTheme.Typography.body))
                    .fontWeight(isSelected ? AppTheme.Typography.semibold : AppTheme.Typography.regular)
                    .foregroundColor(textColor)
                
                Text("\(frequency.count)x daily")
                    .font(.monaco(AppTheme.Typography.caption))
                    .foregroundColor(textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.medium)
            .background(backgroundColor)
            .overlay(border)
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .accessibilityLabel("\(frequency.displayName) frequency")
        .accessibilityValue("\(frequency.count) times daily")
        .accessibilityHint("Select how often to take this item")
    }
    
    // MARK: - Styling Properties
    
    private var textColor: Color {
        isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary
    }
    
    private var backgroundColor: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .fill(isSelected ? AppTheme.Colors.primaryBlue.veryLight() : AppTheme.Colors.backgroundSecondary)
    }
    
    private var border: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .stroke(
                isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.borderLight,
                lineWidth: AppTheme.Dimensions.borderWidth
            )
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.xxLarge) {
        FrequencySelector(
            selectedFrequency: .constant(.twice),
            selectedPeriods: .constant([.breakfast, .dinner]),
            itemType: .medication
        )
        
        Divider()
        
        FrequencySelector(
            selectedFrequency: .constant(.threeTimesDaily),
            selectedPeriods: .constant([.breakfast, .lunch, .dinner]),
            itemType: .diet
        )
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}
