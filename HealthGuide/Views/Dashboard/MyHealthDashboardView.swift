//
//  MyHealthDashboardView.swift
//  HealthGuide/Views/Dashboard/MyHealthDashboardView.swift
//
//  Main dashboard with time-aware medication display and elder-friendly interface
//  Uses reusable TimePeriodSelector for consistent UI patterns
//

import SwiftUI
import CoreSpotlight
import CoreServices

@available(iOS 18.0, *)
struct MyHealthDashboardView: View {
    @StateObject private var viewModel = MyHealthDashboardViewModel()
    @State private var selectedPeriods: [TimePeriod] = [.breakfast]
    @State private var showAddItem = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.backgroundSecondary
                    .ignoresSafeArea()
                
                contentView
            }
            .navigationTitle(currentDateTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addButton
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddItemView()
            }
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
                selectedPeriods = [viewModel.currentPeriod]
            }
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading {
            LoadingView(showSkeleton: true)
        } else if viewModel.hasNoItems {
            emptyStateView
        } else {
            dashboardContent
        }
    }
    
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                periodSelectorSection
                    .padding(.horizontal, AppTheme.Spacing.screenPadding)
                    .padding(.vertical, AppTheme.Spacing.medium)
                
                healthItemsList
                    .padding(.horizontal, AppTheme.Spacing.screenPadding)
                    .padding(.bottom, AppTheme.Spacing.xxxLarge)
            }
        }
    }
    
    private var periodSelectorSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack {
                Text("Time Period")
                    .font(.monaco(AppTheme.Typography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                
                Spacer()
                
                if let currentPeriod = selectedPeriods.first {
                    Text("\(viewModel.itemCount(for: currentPeriod)) items")
                        .font(.monaco(AppTheme.Typography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            
            DashboardPeriodSelector(
                selectedPeriods: $selectedPeriods,
                currentPeriod: viewModel.currentPeriod,
                itemCounts: viewModel.getAllPeriodCounts()
            )
        }
    }
    
    private var healthItemsList: some View {
        LazyVStack(spacing: AppTheme.Spacing.medium) {
            ForEach(itemsForSelectedPeriod, id: \.item.id) { itemData in
                HealthCardView(
                    item: itemData.item,
                    cardType: itemData.item.itemType,
                    period: selectedPeriods.first ?? .breakfast,
                    dose: itemData.dose,
                    onTap: { handleItemTap(itemData.item) },
                    onMarkTaken: { handleMarkTaken(itemData) }
                )
            }
        }
    }
    
    private var emptyStateView: some View {
        EmptyStateView(
            title: "No Medications Scheduled",
            message: "Add your medications, supplements, and diet items to get started",
            systemImage: "heart.text.square",
            actionTitle: "Add First Item",
            action: { showAddItem = true }
        )
    }
    
    private var addButton: some View {
        Button(action: { showAddItem = true }) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: AppTheme.Typography.headline))
                .foregroundColor(AppTheme.Colors.primaryBlue)
        }
        .frame(
            minWidth: AppTheme.Dimensions.minimumTouchTarget,
            minHeight: AppTheme.Dimensions.minimumTouchTarget
        )
        .accessibilityLabel("Add new health item")
        .accessibilityHint("Opens form to add medication, supplement, or diet item")
    }
    
    // MARK: - Computed Properties
    
    private var currentDateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    private var itemsForSelectedPeriod: [(item: any HealthItem, dose: ScheduledDose?)] {
        guard let selectedPeriod = selectedPeriods.first else { return [] }
        return viewModel.itemsForPeriod(selectedPeriod)
    }
    
    // MARK: - Action Handlers
    
    private func handleItemTap(_ item: any HealthItem) {
        #if DEBUG
        print("Tapped item: \(item.name)")
        #endif
        
        // Donate to Spotlight for better search and predictions
        donateToSpotlight(item: item)
    }
    
    private func handleMarkTaken(_ itemData: (item: any HealthItem, dose: ScheduledDose?)) {
        guard let dose = itemData.dose else { return }
        
        Task {
            await viewModel.markDoseTaken(itemId: itemData.item.id, doseId: dose.id)
        }
    }
    
    // MARK: - Spotlight Integration
    
    private func donateToSpotlight(item: any HealthItem) {
        // Create user activity
        let activity = NSUserActivity(activityType: "com.healthguide.viewMedication")
        activity.title = "View \(item.name)"
        activity.userInfo = ["medicationID": item.id.uuidString, "type": item.itemType.rawValue]
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = item.id.uuidString
        
        // Add searchable attributes
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
        attributes.contentDescription = "View details for \(item.name)"
        attributes.keywords = [item.name, item.itemType.displayName, "medication", "health"]
        
        // Add custom attributes based on type
        if let medication = item as? Medication {
            // dosage is non-optional in the Medication struct
            attributes.keywords?.append(medication.dosage)
            // unit is an enum, need to use rawValue
            attributes.keywords?.append(medication.unit.rawValue)
        }
        
        activity.contentAttributeSet = attributes
        activity.becomeCurrent()
    }
}

// MARK: - Dashboard Period Selector
@available(iOS 18.0, *)
struct DashboardPeriodSelector: View {
    @Binding var selectedPeriods: [TimePeriod]
    let currentPeriod: TimePeriod
    let itemCounts: [TimePeriod: Int]
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(TimePeriod.allCases.filter { $0 != .custom }, id: \.self) { period in
                DashboardPeriodButton(
                    period: period,
                    isSelected: selectedPeriods.contains(period),
                    isCurrent: currentPeriod == period,
                    itemCount: itemCounts[period] ?? 0
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriods = [period]
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard Period Button
@available(iOS 18.0, *)
struct DashboardPeriodButton: View {
    let period: TimePeriod
    let isSelected: Bool
    let isCurrent: Bool
    let itemCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.xxSmall) {
                Text(period.displayName)
                    .font(.monaco(isSelected ? AppTheme.Typography.callout : AppTheme.Typography.footnote))
                    .fontWeight(isSelected ? AppTheme.Typography.semibold : AppTheme.Typography.regular)
                    .foregroundColor(textColor)
                
                if itemCount > 0 {
                    itemCountBadge
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(backgroundView)
            .overlay(currentPeriodBorder)
        }
        .frame(
            minWidth: AppTheme.Dimensions.minimumTouchTarget,
            minHeight: AppTheme.Dimensions.minimumTouchTarget
        )
        .contentShape(Rectangle())
        .accessibilityLabel("\(period.displayName) period")
        .accessibilityValue("\(itemCount) items")
        .accessibilityHint("Select to view items for this time period")
    }
    
    private var itemCountBadge: some View {
        Text("\(itemCount)")
            .font(.monaco(AppTheme.Typography.caption))
            .foregroundColor(textColor)
            .padding(.horizontal, AppTheme.Spacing.xSmall)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(badgeBackgroundColor)
            )
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
            .fill(isSelected ? AppTheme.Colors.primaryBlue.veryLight() : Color.clear)
    }
    
    @ViewBuilder
    private var currentPeriodBorder: some View {
        if isCurrent && !isSelected {
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                .stroke(AppTheme.Colors.primaryBlue.light(), lineWidth: AppTheme.Dimensions.borderWidth)
        }
    }
    
    private var textColor: Color {
        isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary
    }
    
    private var badgeBackgroundColor: Color {
        (isSelected ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textSecondary).veryLight()
    }
}

// MARK: - Dashboard View Model
@available(iOS 18.0, *)
@MainActor
final class MyHealthDashboardViewModel: ObservableObject {
    
    @Published var allItems: [(item: any HealthItem, dose: ScheduledDose?)] = []
    @Published var isLoading = true
    @Published var error: AppError?
    
    private let dataProcessor = HealthDataProcessor()
    private var periodCounts: [TimePeriod: Int] = [:]
    
    var currentPeriod: TimePeriod {
        HealthDataProcessor.getCurrentTimePeriod()
    }
    
    var availablePeriods: [TimePeriod] {
        HealthDataProcessor.getAllTimePeriods()
    }
    
    var hasNoItems: Bool {
        allItems.isEmpty
    }
    
    func itemCount(for period: TimePeriod) -> Int {
        periodCounts[period] ?? 0
    }
    
    func getAllPeriodCounts() -> [TimePeriod: Int] {
        periodCounts
    }
    
    func itemsForPeriod(_ period: TimePeriod) -> [(item: any HealthItem, dose: ScheduledDose?)] {
        allItems.filter { $0.dose?.period == period }
    }
    
    func loadData() async {
        isLoading = true
        error = nil
        
        do {
            let processedData = try await dataProcessor.processHealthDataForToday()
            allItems = processedData.items
            periodCounts = processedData.periodCounts
            isLoading = false
        } catch {
            self.error = error as? AppError ?? AppError.coreDataFetchFailed
            isLoading = false
        }
    }
    
    func markDoseTaken(itemId: UUID, doseId: UUID) async {
        do {
            let processedData = try await dataProcessor.markDoseTakenAndRefresh(
                itemId: itemId,
                doseId: doseId
            )
            allItems = processedData.items
            periodCounts = processedData.periodCounts
        } catch {
            self.error = error as? AppError ?? AppError.coreDataSaveFailed
        }
    }
}

// MARK: - Preview
#Preview {
    MyHealthDashboardView()
}
