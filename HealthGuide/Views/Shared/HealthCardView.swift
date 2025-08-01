//
//  HealthCardView.swift
//  HealthGuide
//
//  Reusable card component for medications, supplements, and diet
//  Elder-friendly with large touch targets and clear visual hierarchy
//

import SwiftUI

@available(iOS 18.0, *)
struct HealthCardView: View {
    let item: any HealthItem
    let cardType: HealthItemType
    let period: TimePeriod
    let dose: ScheduledDose?
    let onTap: () -> Void
    let onMarkTaken: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Header
                cardHeader
                
                // Content
                cardContent
                    .padding(AppTheme.Spacing.cardPadding)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(AppTheme.Effects.glassOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .stroke(AppTheme.Colors.borderLight, lineWidth: AppTheme.Dimensions.borderWidth)
            )
            .shadow(
                color: Color.black.opacity(AppTheme.Effects.cardShadowOpacity),
                radius: AppTheme.Effects.cardShadowRadius,
                x: 0,
                y: 4
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { pressing in
            isPressed = pressing
        } perform: {}
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(AppStrings.AddItem.typeLabel)
    }
    
    // MARK: - Header
    private var cardHeader: some View {
        HStack {
            Text(cardType.displayName)
                .font(.monaco(AppTheme.Typography.cardHeader))
                .fontWeight(AppTheme.Typography.bold)
                .foregroundColor(AppTheme.Colors.textOnDark)
                .padding(.horizontal, AppTheme.Spacing.cardHeaderPadding)
                .padding(.vertical, AppTheme.Spacing.xSmall)
            
            Spacer()
        }
        .background(cardType.headerColor)
    }
    
    // MARK: - Content
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            // Item name and dosage
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text(item.displayName)
                    .font(.monaco(AppTheme.Typography.medicationName))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                
                if let medication = item as? Medication {
                    Text(medication.fullDosageDescription)
                        .font(.monaco(AppTheme.Typography.medicationDose))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } else if let supplement = item as? Supplement {
                    Text(supplement.fullDosageDescription)
                        .font(.monaco(AppTheme.Typography.medicationDose))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                } else if let diet = item as? Diet {
                    Text(diet.portion)
                        .font(.monaco(AppTheme.Typography.medicationDose))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            
            // Time and status
            HStack {
                if let dose = dose {
                    doseStatusBadge(for: dose)
                }
                
                Spacer()
                
                if let dose = dose, !dose.isTaken {
                    markTakenButton
                }
            }
            
            // Notes if present
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .italic()
                    .lineLimit(2)
            }
        }
    }
    
    // MARK: - Dose Status Badge
    private func doseStatusBadge(for dose: ScheduledDose) -> some View {
        HStack(spacing: AppTheme.Spacing.xxSmall) {
            Image(systemName: dose.isTaken ? "checkmark.circle.fill" : "clock.fill")
                .foregroundColor(doseStatusColor(for: dose))
            
            Text(doseStatusText(for: dose))
                .font(.monaco(AppTheme.Typography.caption))
                .foregroundColor(doseStatusColor(for: dose))
        }
        .padding(.horizontal, AppTheme.Spacing.xSmall)
        .padding(.vertical, AppTheme.Spacing.xxSmall)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.badgeCornerRadius)
                .fill(doseStatusColor(for: dose).opacity(0.1))
        )
    }
    
    // MARK: - Mark Taken Button
    private var markTakenButton: some View {
        Button(action: onMarkTaken) {
            Text(AppStrings.Status.taken)
                .font(.monaco(AppTheme.Typography.footnote))
                .fontWeight(AppTheme.Typography.medium)
                .foregroundColor(AppTheme.Colors.primaryBlue)
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.xxSmall)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                        .stroke(AppTheme.Colors.primaryBlue, lineWidth: AppTheme.Dimensions.borderWidth)
                )
        }
        .frame(minWidth: AppTheme.Dimensions.minimumTouchTarget, 
               minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .contentShape(Rectangle())
    }
    
    // MARK: - Helper Methods
    private func doseStatusColor(for dose: ScheduledDose) -> Color {
        if dose.isTaken {
            return AppTheme.Semantic.completed
        } else if dose.isPastDue {
            return AppTheme.Semantic.pastDue
        } else if dose.isCurrent {
            return AppTheme.Semantic.current
        } else {
            return AppTheme.Semantic.upcoming
        }
    }
    
    private func doseStatusText(for dose: ScheduledDose) -> String {
        if dose.isTaken {
            return dose.takenAt?.relativeTimeString ?? AppStrings.Status.taken
        } else if dose.isPastDue {
            return AppStrings.Status.due
        } else {
            return dose.time.relativeTimeString
        }
    }
    
    private var accessibilityDescription: String {
        var description = "\(cardType.displayName): \(item.displayName)"
        if let dose = dose {
            description += ", \(doseStatusText(for: dose))"
        }
        return description
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.medium) {
        HealthCardView(
            item: Medication.sampleMetformin,
            cardType: .medication,
            period: .breakfast,
            dose: ScheduledDose(time: Date(), period: .breakfast),
            onTap: {},
            onMarkTaken: {}
        )
        
        HealthCardView(
            item: Supplement.sampleVitaminD,
            cardType: .supplement,
            period: .lunch,
            dose: ScheduledDose(time: Date().addingHours(2), period: .lunch),
            onTap: {},
            onMarkTaken: {}
        )
        
        HealthCardView(
            item: Diet.sampleBreakfast,
            cardType: .diet,
            period: .breakfast,
            dose: ScheduledDose(time: Date().addingHours(-1), period: .breakfast, isTaken: true, takenAt: Date().addingHours(-1)),
            onTap: {},
            onMarkTaken: {}
        )
    }
    .padding()
    .background(AppTheme.Colors.backgroundSecondary)
}