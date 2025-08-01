//
//  ScheduleSelector.swift
//  HealthGuide/Views/AddItem/ScheduleSelector.swift
//
//  Date selection for health item scheduling with elder-friendly interface
//  Swift 6 compliant with proper state management
//

import SwiftUI

@available(iOS 18.0, *)
struct ScheduleSelector: View {
    @Binding var selectedDays: Set<Date>
    @State private var availableDays: [Date] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            dayCheckboxList
            quickActions
        }
        .onAppear {
            setupAvailableDays()
        }
    }
    
    // MARK: - Components
    
    private var dayCheckboxList: some View {
        VStack(spacing: AppTheme.Spacing.small) {
            ForEach(availableDays, id: \.self) { date in
                DayCheckbox(
                    date: date,
                    isSelected: selectedDays.contains(date),
                    action: {
                        toggleDay(date)
                    }
                )
            }
        }
    }
    
    private var quickActions: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Button(action: selectAll) {
                Text("Select All")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
            }
            .disabled(selectedDays.count == availableDays.count)
            
            Button(action: deselectAll) {
                Text("Clear All")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .disabled(selectedDays.isEmpty)
            
            Spacer()
            
            Text("\(selectedDays.count) of \(availableDays.count) days")
                .font(.monaco(AppTheme.Typography.caption))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }
    
    // MARK: - Actions
    
    private func setupAvailableDays() {
        availableDays = Date.generateDatesForNext(Configuration.HealthLimits.scheduleDaysAhead)
        
        if selectedDays.isEmpty {
            selectedDays = Set(availableDays)
        }
    }
    
    private func toggleDay(_ date: Date) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedDays.contains(date) {
                selectedDays.remove(date)
            } else {
                selectedDays.insert(date)
            }
        }
    }
    
    private func selectAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDays = Set(availableDays)
        }
    }
    
    private func deselectAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDays.removeAll()
        }
    }
}

// MARK: - Day Checkbox
@available(iOS 18.0, *)
struct DayCheckbox: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: AppTheme.Dimensions.checkboxSize))
                    .foregroundColor(isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.borderMedium)
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                    Text(dayLabel(for: date))
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(AppTheme.Typography.medium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(date.monthDay)
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                Text(date.dayOfWeek)
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .padding(AppTheme.Spacing.medium)
            .background(backgroundColor)
            .overlay(border)
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .accessibilityLabel("Schedule for \(dayLabel(for: date))")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Tap to toggle day selection")
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
    
    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            return date.dayOfWeek
        }
    }
}

// MARK: - Calendar Grid Selector
@available(iOS 18.0, *)
struct CalendarScheduleSelector: View {
    @Binding var selectedDays: Set<Date>
    @State private var availableDays: [Date] = []
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 5)
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Next 5 Days")
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.small) {
                ForEach(availableDays, id: \.self) { date in
                    CalendarDayButton(
                        date: date,
                        isSelected: selectedDays.contains(date),
                        action: {
                            toggleDay(date)
                        }
                    )
                }
            }
        }
        .onAppear {
            setupAvailableDays()
        }
    }
    
    private func setupAvailableDays() {
        availableDays = Date.generateDatesForNext(Configuration.HealthLimits.scheduleDaysAhead)
        if selectedDays.isEmpty {
            selectedDays = Set(availableDays)
        }
    }
    
    private func toggleDay(_ date: Date) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedDays.contains(date) {
                selectedDays.remove(date)
            } else {
                selectedDays.insert(date)
            }
        }
    }
}

// MARK: - Calendar Day Button
@available(iOS 18.0, *)
struct CalendarDayButton: View {
    let date: Date
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xxSmall) {
                Text(String(date.dayOfWeek.prefix(3)))
                    .font(.monaco(AppTheme.Typography.caption))
                    .foregroundColor(isSelected ? .white : AppTheme.Colors.textSecondary)
                
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.monaco(AppTheme.Typography.body))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(isSelected ? .white : AppTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(backgroundColor)
            .overlay(todayBorder)
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .accessibilityLabel("Schedule for \(date.dayOfWeek)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Tap to toggle day selection")
    }
    
    private var backgroundColor: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .fill(isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.backgroundSecondary)
    }
    
    @ViewBuilder
    private var todayBorder: some View {
        if Calendar.current.isDateInToday(date) {
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                .stroke(AppTheme.Colors.primaryBlue, lineWidth: AppTheme.Dimensions.focusBorderWidth)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.xxLarge) {
        VStack(alignment: .leading) {
            Text("List Style")
                .font(.headline)
            ScheduleSelector(selectedDays: .constant(Set(Date.generateDatesForNext(3))))
        }
        
        Divider()
        
        VStack(alignment: .leading) {
            Text("Calendar Style")
                .font(.headline)
            CalendarScheduleSelector(selectedDays: .constant(Set([Date()])))
        }
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}
