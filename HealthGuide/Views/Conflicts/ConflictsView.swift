//
//  ConflictsView.swift
//  HealthGuide
//
//  Drug interaction warnings display
//  Elder-friendly interface with clear severity indicators
//

import SwiftUI
import CoreData

@available(iOS 18.0, *)
struct ConflictsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ConflictEntity.severity, ascending: false),
                         NSSortDescriptor(keyPath: \ConflictEntity.checkedAt, ascending: false)],
        animation: .default)
    private var conflicts: FetchedResults<ConflictEntity>
    
    @State private var filterSeverity: ConflictSeverity?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Warm off-white gradient background for reduced eye strain
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "F8F8F8"),
                        Color(hex: "FAFAFA")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                contentView
            }
            .navigationTitle(AppStrings.TabBar.conflicts)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    filterMenu
                }
            }
        }
        .onAppear {
            print("🔍 DEBUG: ConflictsView appearing")
            print("🔍 DEBUG: Conflicts count: \(conflicts.count)")
            for conflict in conflicts {
                print("  - Conflict: \(conflict.medicationA ?? "nil") + \(conflict.medicationB ?? "nil")")
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if filteredConflicts.isEmpty {
            emptyStateView
        } else {
            conflictsList
        }
    }
    
    private var conflictsList: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.medium) {
                if hasHighSeverityConflicts {
                    warningBanner
                }
                
                ForEach(filteredConflicts) { conflict in
                    ConflictCardView(conflict: conflict)
                }
            }
            .padding(AppTheme.Spacing.screenPadding)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.successGreen)
            
            Text(filterSeverity == nil ? "No Conflicts Found" : "No Conflicts in Filter")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(filterSeverity == nil ? "Your medications are safe to take together" : "No conflicts found in selected category")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Spacer()
        }
    }
    
    private var warningBanner: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: AppTheme.ElderTypography.headline))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxSmall) {
                Text("High Priority Conflicts")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(.white)
                
                Text("Always consult your healthcare provider")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.errorRed)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
    
    private var filterMenu: some View {
        Menu {
            Button(action: { filterSeverity = nil }) {
                if filterSeverity == nil {
                    Label("All Conflicts", systemImage: "checkmark")
                } else {
                    Text("All Conflicts")
                }
            }
            
            ForEach(ConflictSeverity.allCases, id: \.self) { severity in
                Button(action: { filterSeverity = severity }) {
                    if filterSeverity == severity {
                        Label(severity.displayName, systemImage: "checkmark")
                    } else {
                        Text(severity.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
                .frame(
                    minWidth: AppTheme.Dimensions.minimumTouchTarget,
                    minHeight: AppTheme.Dimensions.minimumTouchTarget
                )
        }
    }
    
    private var filteredConflicts: [ConflictEntity] {
        if let filterSeverity = filterSeverity {
            return conflicts.filter { $0.severity == filterSeverity.rawValue }
        }
        return Array(conflicts)
    }
    
    private var hasHighSeverityConflicts: Bool {
        filteredConflicts.contains { $0.severity == ConflictSeverity.high.rawValue }
    }
}

// MARK: - Conflict Card View
@available(iOS 18.0, *)
struct ConflictCardView: View {
    let conflict: ConflictEntity
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            HStack {
                    SeverityIndicator(severity: ConflictSeverity(rawValue: conflict.severity ?? "") ?? .low)
                    
                    Spacer()
                    
                    if let checkedAt = conflict.checkedAt {
                        Text(checkedAt.relativeTimeString)
                            .font(.monaco(AppTheme.ElderTypography.caption))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("\(conflict.medicationA ?? "") + \(conflict.medicationB ?? "")")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(AppTheme.Typography.semibold)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text(conflict.conflictDescription ?? "Interaction details unavailable")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(3)
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(AppTheme.Colors.backgroundSecondary)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .stroke(
                    ConflictSeverity(rawValue: conflict.severity ?? "")?.color.opacity(0.3) ?? Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Severity Indicator
@available(iOS 18.0, *)
struct SeverityIndicator: View {
    let severity: ConflictSeverity
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxSmall) {
            Image(systemName: severity.iconName)
                .font(.system(size: AppTheme.ElderTypography.footnote))
            
            Text(severity.displayName)
                .font(.monaco(AppTheme.ElderTypography.caption))
                .fontWeight(AppTheme.Typography.semibold)
        }
        .foregroundColor(severity.color)
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.xxSmall)
        .background(severity.color.opacity(0.1))
        .cornerRadius(AppTheme.Dimensions.inputCornerRadius)
    }
}

// MARK: - Conflict Severity
@available(iOS 18.0, *)
enum ConflictSeverity: String, CaseIterable {
    case high = "high"
    case moderate = "moderate"
    case low = "low"
    
    var displayName: String {
        switch self {
        case .high: return "High"
        case .moderate: return "Moderate"
        case .low: return "Low"
        }
    }
    
    var iconName: String {
        switch self {
        case .high: return "exclamationmark.triangle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .low: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .high: return AppTheme.Colors.errorRed
        case .moderate: return AppTheme.Colors.warningOrange
        case .low: return AppTheme.Colors.primaryBlue
        }
    }
}

// MARK: - Preview
#Preview {
    ConflictsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}