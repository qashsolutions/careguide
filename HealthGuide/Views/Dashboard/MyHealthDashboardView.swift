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
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = MyHealthDashboardViewModel()
    @State private var selectedPeriods: [TimePeriod] = [.breakfast]
    @State private var showAddItem = false
    @State private var showTakeConfirmation = false
    @State private var pendingDoseToMark: (item: any HealthItem, dose: ScheduledDose?)? = nil
    @State private var tappedItemId: UUID? = nil
    @State private var hasLoadedData = false
    
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
            .navigationTitle("My Health")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Add button
                    addButton
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddItemView()
                    .onDisappear {
                        // Refresh data when sheet closes
                        // TODO: Optimize to only refresh when item actually added
                        Task {
                            await viewModel.loadData()
                        }
                    }
            }
            .refreshable {
                // Debounce refresh to prevent rapid reloads
                try? await Task.sleep(for: .seconds(0.5))
                await viewModel.loadData()
            }
            .task {
                // Only load data once when view first appears
                guard !hasLoadedData else { 
                    // Silently skip - no need to log
                    return 
                }
                
                print("🔍 DEBUG: MyHealthDashboardView loading data for first time...")
                await viewModel.loadData()
                selectedPeriods = [viewModel.currentPeriod]
                hasLoadedData = true
                print("🔍 DEBUG: Loaded \(viewModel.allItems.count) items")
                for item in viewModel.allItems {
                    let iconName = item.item.itemType.iconName
                    if iconName.isEmpty {
                        print("  ❌ Empty icon for: \(item.item.name)")
                    }
                }
            }
            // Disabled - causing excessive refreshes and high energy usage
            // .onReceive(NotificationCenter.default.publisher(for: .coreDataDidSave)) { _ in
            //     Task {
            //         await viewModel.loadData()
            //     }
            // }
            .alert("Take Medication", isPresented: $showTakeConfirmation) {
                Button("Yes", role: .none) {
                    if let pending = pendingDoseToMark {
                        confirmMarkTaken(pending)
                    }
                }
                Button("No", role: .cancel) {
                    pendingDoseToMark = nil
                }
            } message: {
                if let pending = pendingDoseToMark {
                    Text("Have you taken \(pending.item.name)?")
                } else {
                    Text("Have you taken this medication?")
                }
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
            VStack(spacing: AppTheme.Spacing.medium) {
                // Show all time periods with their medications
                allTimePeriodsView
                    .padding(.horizontal, AppTheme.Spacing.screenPadding)
                    .padding(.vertical, AppTheme.Spacing.medium)
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
    
    private var allTimePeriodsView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            // Show each time period with its medications
            ForEach(TimePeriod.allCases.filter { $0 != .custom && $0 != .bedtime }, id: \.self) { period in
                timePeriodSection(for: period)
            }
        }
    }
    
    
    private func shouldHighlightPeriod(_ period: TimePeriod) -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        switch period {
        case .breakfast:
            return hour >= 6 && hour < 11
        case .lunch:
            return hour >= 11 && hour < 18
        case .dinner:
            return hour >= 18 || hour < 6
        default:
            return false
        }
    }
    
    private func timePeriodSection(for period: TimePeriod) -> some View {
        let items = viewModel.itemsForPeriod(period)
        let isCurrentPeriod = period == viewModel.currentPeriod
        let shouldHighlight = shouldHighlightPeriod(period)
        
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // Period header
            HStack {
                Label {
                    Text(period.displayName)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(isCurrentPeriod ? .semibold : .regular)
                } icon: {
                    Image(systemName: period.iconName.isEmpty ? "clock" : period.iconName)
                        .font(.system(size: 20))
                }
                .foregroundColor(isCurrentPeriod ? Color.blue : AppTheme.Colors.textPrimary)
                
                Spacer()
                
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isCurrentPeriod ? Color.blue : Color.gray)
                        )
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                    .fill(isCurrentPeriod ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
            )
            
            // Medications list
            if items.isEmpty {
                Text("No items scheduled")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .italic()
                    .padding(.leading, AppTheme.Spacing.medium)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(items, id: \.item.id) { itemData in
                        medicationRow(itemData: itemData, period: period)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .overlay(
            shouldHighlight ? 
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .stroke(AppTheme.Colors.primaryBlue, lineWidth: 2) : nil
        )
    }
    
    private func medicationRow(itemData: (item: any HealthItem, dose: ScheduledDose?), period: TimePeriod) -> some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Icon (with fallback for empty names)
            Image(systemName: itemData.item.itemType.iconName.isEmpty ? "questionmark.circle" : itemData.item.itemType.iconName)
                .font(.system(size: 24))
                .foregroundColor(itemData.item.itemType.color)
                .frame(width: 36)
            
            // Name and dosage
            VStack(alignment: .leading, spacing: 2) {
                Text(itemData.item.name)
                    .font(.monaco(AppTheme.ElderTypography.medicationName))
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                if let medication = itemData.item as? Medication {
                    Text(medication.dosage)
                        .font(.monaco(AppTheme.ElderTypography.medicationDose))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            // Mark taken button
            Button(action: {
                // Set visual feedback
                tappedItemId = itemData.item.id
                
                // Create dose if needed
                if itemData.dose == nil {
                    let calendar = Calendar.current
                    let time = calendar.date(bySettingHour: period.defaultTime.hour,
                                           minute: period.defaultTime.minute,
                                           second: 0,
                                           of: Date()) ?? Date()
                    let tempDose = ScheduledDose(time: time, period: period)
                    pendingDoseToMark = (item: itemData.item, dose: tempDose)
                } else {
                    pendingDoseToMark = itemData
                }
                
                // Show confirmation dialog
                showTakeConfirmation = true
            }) {
                Image(systemName: itemData.dose?.isTaken == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundColor(tappedItemId == itemData.item.id ? Color.blue : 
                                   (itemData.dose?.isTaken == true ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary))
                    .scaleEffect(tappedItemId == itemData.item.id ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: tappedItemId)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.xSmall)
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
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 80))
                .foregroundColor(AppTheme.Colors.primaryBlue)
            
            Text("Care Management")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Add & Manage Medications, Diet, Supplements")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Button(action: { showAddItem = true }) {
                Text("Add First Item")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .background(AppTheme.Colors.primaryBlue)
                    .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            }
            .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Spacer()
        }
    }
    
    private var addButton: some View {
        Button(action: { showAddItem = true }) {
            Image(systemName: "plus")
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
    
    private func confirmMarkTaken(_ itemData: (item: any HealthItem, dose: ScheduledDose?)) {
        guard let dose = itemData.dose else { 
            print("⚠️ No dose to mark as taken")
            return 
        }
        
        Task {
            print("✅ Marking dose as taken for: \(itemData.item.name)")
            await viewModel.markDoseTaken(itemId: itemData.item.id, doseId: dose.id)
            pendingDoseToMark = nil
            tappedItemId = nil // Clear visual feedback
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
