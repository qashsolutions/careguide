//
//  ItemTypeSelector.swift
//  HealthGuide
//
//  Segmented control for selecting health item type
//  Elder-friendly with large touch targets and clear visuals
//

import SwiftUI

@available(iOS 18.0, *)
struct ItemTypeSelector: View {
    @Binding var selectedType: HealthItemType
    @State private var animationID = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(AppStrings.AddItem.typeLabel)
                .font(.monaco(AppTheme.Typography.footnote))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            HStack(spacing: 0) {
                ForEach(HealthItemType.allCases, id: \.self) { type in
                    ItemTypeButton(
                        type: type,
                        isSelected: selectedType == type,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedType = type
                                animationID = UUID()
                            }
                        }
                    )
                }
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                        .fill(AppTheme.Colors.backgroundSecondary)
                    
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                            .fill(selectedType.headerColor)
                            .frame(width: geometry.size.width / CGFloat(HealthItemType.allCases.count))
                            .offset(x: offsetForType(selectedType, in: geometry.size.width))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: animationID)
                    }
                }
                .allowsHitTesting(false)
            )
        }
    }
    
    private func offsetForType(_ type: HealthItemType, in totalWidth: CGFloat) -> CGFloat {
        let buttonWidth = totalWidth / CGFloat(HealthItemType.allCases.count)
        let index = CGFloat(HealthItemType.allCases.firstIndex(of: type) ?? 0)
        return buttonWidth * index
    }
}

// MARK: - Item Type Button
@available(iOS 18.0, *)
struct ItemTypeButton: View {
    let type: HealthItemType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xxSmall) {
                Image(systemName: type.iconName)
                    .font(.system(size: AppTheme.Typography.headline))
                    .foregroundColor(isSelected ? .white : AppTheme.Colors.textSecondary)
                
                Text(type.rawValue)
                    .font(.monaco(AppTheme.Typography.footnote))
                    .fontWeight(isSelected ? AppTheme.Typography.semibold : AppTheme.Typography.regular)
                    .foregroundColor(isSelected ? .white : AppTheme.Colors.textSecondary)
            }
            .zIndex(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.medium)
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
        .accessibilityElement()
        .accessibilityLabel("\(type.displayName) \(isSelected ? "selected" : "")")
        .accessibilityHint("Tap to select \(type.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Visual Style Selector
@available(iOS 18.0, *)
struct VisualItemTypeSelector: View {
    @Binding var selectedType: HealthItemType
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text(AppStrings.AddItem.typeLabel)
                .font(.monaco(AppTheme.Typography.headline))
                .fontWeight(AppTheme.Typography.semibold)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(spacing: AppTheme.Spacing.small) {
                ForEach(HealthItemType.allCases, id: \.self) { type in
                    VisualTypeCard(
                        type: type,
                        isSelected: selectedType == type,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedType = type
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Visual Type Card
@available(iOS 18.0, *)
struct VisualTypeCard: View {
    let type: HealthItemType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.medium) {
                // Icon
                ZStack {
                    Circle()
                        .fill(type.headerColor.opacity(isSelected ? 1.0 : 0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: type.iconName)
                        .font(.system(size: AppTheme.Typography.headline))
                        .foregroundColor(isSelected ? .white : type.headerColor)
                }
                
                // Text
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                    Text(type.displayName)
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(AppTheme.Typography.semibold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(descriptionForType(type))
                        .font(.monaco(AppTheme.Typography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: AppTheme.Typography.headline))
                    .foregroundColor(isSelected ? type.headerColor : AppTheme.Colors.borderMedium)
            }
            .padding(AppTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(isSelected ? type.headerColor.veryLight() : AppTheme.Colors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .stroke(isSelected ? type.headerColor : AppTheme.Colors.borderLight, lineWidth: AppTheme.Dimensions.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
    }
    
    private func descriptionForType(_ type: HealthItemType) -> String {
        switch type {
        case .medication:
            return "Prescription and over-the-counter drugs"
        case .supplement:
            return "Vitamins, minerals, and natural products"
        case .diet:
            return "Meals, snacks, and special diets"
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: AppTheme.Spacing.xxLarge) {
        // Compact selector
        VStack {
            Text("Compact Style")
                .font(.headline)
            ItemTypeSelector(selectedType: .constant(.medication))
        }
        
        Divider()
        
        // Visual selector
        VStack {
            Text("Visual Style")
                .font(.headline)
            VisualItemTypeSelector(selectedType: .constant(.supplement))
        }
    }
    .padding()
    .background(AppTheme.Colors.backgroundPrimary)
}