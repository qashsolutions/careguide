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
    @StateObject private var groupService = FirebaseGroupService.shared
    @StateObject private var groupDataService = FirebaseGroupDataService.shared
    private let dataProcessor = HealthDataProcessor.shared
    @State private var selectedPeriods: [TimePeriod] = [.breakfast]
    @State private var showAddItem = false
    @State private var showTakeConfirmation = false
    @State private var pendingDoseToMark: (item: any HealthItem, dose: ScheduledDose?)? = nil
    @State private var tappedItemId: UUID? = nil
    @State private var hasLoadedData = false
    @State private var showNoPermissionAlert = false
    @State private var lastGroupId: String? = nil
    @State private var isLoadingData = false
    @State private var refreshTimer: Timer? = nil
    @State private var doseListenerRegistration: Any? = nil
    @State private var selectedMedication: Medication? = nil
    @State private var showMedicationDetail = false
    
    // Use AppStorage to persist last refresh time across app launches
    @AppStorage("lastHealthDataRefresh") private var lastRefreshTimestamp: Double = 0
    private let refreshInterval: TimeInterval = 3600 // 1 hour
    
    // Lazy notification setup
    @AppStorage("hasHealthItems") private var hasHealthItems = false
    @AppStorage("notificationsSetup") private var notificationsSetup = false
    @AppStorage("lastNotificationCheck") private var lastNotificationCheck: Double = 0
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("My Health")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        addButton
                    }
                }
                .sheet(isPresented: $showAddItem) {
                    addItemSheet
                }
                .refreshable {
                    await handleRefresh()
                }
                .task {
                    await handleInitialLoad()
                }
                .onDisappear {
                    handleViewDisappear()
                }
                .onChange(of: groupService.currentGroup?.id) { oldValue, newValue in
                    handleGroupChange(oldValue: oldValue, newValue: newValue)
                }
                .onChange(of: viewModel.allItems.count) { oldValue, newValue in
                // Check if we have items and need to setup notifications
                if newValue > 0 {
                    hasHealthItems = true
                    
                    // Check if we need to setup notifications (once per day max)
                    let lastCheck = Date(timeIntervalSince1970: lastNotificationCheck)
                    let calendar = Calendar.current
                    
                    if !notificationsSetup || !calendar.isDateInToday(lastCheck) {
                        // Setup notifications in background to avoid blocking UI
                        Task.detached(priority: .background) {
                            print("📱 Setting up notifications lazily...")
                            
                            // Check and request permission if needed
                            await NotificationManager.shared.checkNotificationStatus()
                            
                            let isEnabled = await NotificationManager.shared.isNotificationEnabled
                            if !isEnabled {
                                print("📱 Requesting notification permission...")
                                let granted = await NotificationManager.shared.requestNotificationPermission()
                                print("📱 Permission granted: \(granted)")
                            }
                            
                            let isEnabledAfterRequest = await NotificationManager.shared.isNotificationEnabled
                            if isEnabledAfterRequest {
                                // Schedule notifications
                                await MedicationNotificationScheduler.shared.scheduleDailyNotifications()
                                
                                await MainActor.run {
                                    self.notificationsSetup = true
                                    self.lastNotificationCheck = Date().timeIntervalSince1970
                                    print("✅ Notifications setup complete")
                                }
                            }
                        }
                    }
                } else {
                    hasHealthItems = false
                    notificationsSetup = false
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
            .alert("View Only Access", isPresented: $showNoPermissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Contact your group admin to make changes")
            }
            .sheet(isPresented: $showMedicationDetail) {
                if let medication = selectedMedication {
                    MedicationDetailView(medication: medication)
                }
            }
            .tint(Color.blue)  // Force blue tint for all interactive elements
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            // Show read-only banner at the top if applicable
            ReadOnlyBanner()
            
            if viewModel.isLoading {
                LoadingView(showSkeleton: true)
            } else if viewModel.hasNoItems {
                emptyStateView
            } else {
                dashboardContent
            }
        }
    }
    
    private var dashboardContent: some View {
        // List now handles scrolling, no need for ScrollView
        allTimePeriodsView
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
    
    // MARK: - Extracted View Components
    
    private var mainContent: some View {
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
    }
    
    private var addItemSheet: some View {
        AddItemView()
            .onDisappear {
                // Only primary users can add items
                // They see changes immediately when they add
                if groupService.userHasWritePermission {
                    Task {
                        // Invalidate cache and force refresh for primary user
                        await dataProcessor.invalidateCache()
                        await viewModel.loadData(forceRefresh: true)
                    }
                }
            }
    }
    
    // MARK: - Action Handlers
    
    private func handleRefresh() async {
        // Manual pull-to-refresh - always works regardless of timer
        print("🔄 Manual refresh requested by user")
        await forceRefreshData()
    }
    
    private func handleInitialLoad() async {
        // Initial load on view appear
        await loadDataWithRefreshCheck()
        
        // Setup periodic refresh timer (every 3600 seconds)
        setupRefreshTimer()
        
        // Setup real-time listener for dose updates when in a group
        if groupService.currentGroup != nil {
            setupDoseListener()
        }
    }
    
    private func handleViewDisappear() {
        // Clean up timer when view disappears
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        // Clean up dose listener
        cleanupDoseListener()
    }
    
    private func setupDoseListener() {
        guard let groupId = groupService.currentGroup?.id else { return }
        
        print("🔊 Setting up real-time dose listener for group: \(groupId)")
        
        // Listen to dose changes in Firebase
        NotificationCenter.default.addObserver(
            forName: .groupDataDidChange,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let collection = userInfo["collection"] as? String,
               collection == "doses" {
                print("🔄 Dose data changed in Firebase - refreshing view")
                Task {
                    await self.viewModel.loadData(forceRefresh: true)
                }
            }
        }
    }
    
    private func cleanupDoseListener() {
        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: .groupDataDidChange, object: nil)
    }
    
    private func handleGroupChange(oldValue: String?, newValue: String?) {
        // Only reload if group actually changed (prevents infinite loops)
        if oldValue != newValue && newValue != nil {
            Task {
                print("📱 Group changed from \(oldValue ?? "none") to \(newValue ?? "none")")
                // Force refresh when joining a new group
                hasLoadedData = false
                lastRefreshTimestamp = 0 // Reset timer for new group
                await forceRefreshData()
                hasLoadedData = true
            }
        }
    }
    
    private var allTimePeriodsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(TimePeriod.allCases.filter { $0 != .custom && $0 != .bedtime }, id: \.self) { period in
                    timePeriodCard(for: period)
                }
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    
    private func timePeriodCard(for period: TimePeriod) -> some View {
        let items = viewModel.itemsForPeriod(period)
        let isCurrentPeriod = shouldHighlightPeriod(period)
        
        return VStack(spacing: 0) {
            // Header
            HStack {
                Label {
                    Text(period.displayName)
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .fontWeight(isCurrentPeriod ? .bold : .regular)
                } icon: {
                    Image(systemName: period.iconName.isEmpty ? "clock" : period.iconName)
                        .font(.system(size: 20))
                }
                .foregroundColor(isCurrentPeriod ? AppTheme.Colors.primaryBlue : AppTheme.Colors.textPrimary)
                
                Spacer()
                
                if isCurrentPeriod {
                    Text("NOW")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.primaryBlue)
                        )
                }
                
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                        )
                }
            }
            .padding()
            .background(isCurrentPeriod ? AppTheme.Colors.primaryBlue.opacity(0.05) : Color(UIColor.secondarySystemGroupedBackground))
            
            Divider()
            
            // Content
            if items.isEmpty {
                Text("No items scheduled")
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .italic()
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, itemData in
                        medicationRow(itemData: itemData, period: period)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(index == items.count - 1 ? .hidden : .visible)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Only show delete if item is NOT taken and user has permission
                                let isTaken = itemData.dose?.isTaken ?? false
                                if !isTaken && groupService.userHasWritePermission {
                                    Button(role: .destructive) {
                                        Task {
                                            if let medication = itemData.item as? Medication {
                                                await deleteMedication(medication)
                                            }
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onTapGesture {
                                if let medication = itemData.item as? Medication {
                                    selectedMedication = medication
                                    showMedicationDetail = true
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(items.count * 80)) // Approximate height per row
                .scrollDisabled(true)
            }
        }
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrentPeriod ? AppTheme.Colors.primaryBlue : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func shouldHighlightPeriod(_ period: TimePeriod) -> Bool {
        // Use the same logic as HealthDataProcessor.getCurrentTimePeriod()
        // to ensure consistency
        let currentPeriod = HealthDataProcessor.getCurrentTimePeriod()
        return period == currentPeriod
    }
    
    
    private func medicationRow(itemData: (item: any HealthItem, dose: ScheduledDose?), period: TimePeriod) -> some View {
        let isTaken = itemData.dose?.isTaken == true
        
        return HStack(spacing: AppTheme.Spacing.medium) {
            // Icon (with fallback for empty names)
            Image(systemName: itemData.item.itemType.iconName.isEmpty ? "questionmark.circle" : itemData.item.itemType.iconName)
                .font(.system(size: 24))
                .foregroundColor(isTaken ? Color.gray : itemData.item.itemType.color)
                .frame(width: 36)
            
            // Name and dosage
            VStack(alignment: .leading, spacing: 2) {
                Text(itemData.item.name)
                    .font(.monaco(AppTheme.ElderTypography.medicationName))
                    .foregroundColor(isTaken ? Color.gray : AppTheme.Colors.textPrimary)
                    .strikethrough(isTaken)
                
                if let medication = itemData.item as? Medication {
                    Text(medication.dosage)
                        .font(.monaco(AppTheme.ElderTypography.medicationDose))
                        .foregroundColor(isTaken ? Color.gray.opacity(0.7) : AppTheme.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            // Mark taken button (disabled for read-only users or already taken)
            Button(action: {
                // Don't allow marking if already taken
                if isTaken {
                    return
                }
                
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
                Image(systemName: isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundColor(tappedItemId == itemData.item.id ? Color.blue : 
                                   (isTaken ? AppTheme.Colors.successGreen : AppTheme.Colors.textSecondary))
                    .scaleEffect(tappedItemId == itemData.item.id ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: tappedItemId)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .disabled(!groupService.userHasWritePermission || isTaken)
            .opacity(groupService.userHasWritePermission && !isTaken ? 1.0 : 0.5)
        }
        .padding(.horizontal, AppTheme.Spacing.small)
        .padding(.vertical, AppTheme.Spacing.xSmall)
        .opacity(isTaken ? 0.6 : 1.0)
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
            
            if groupService.userHasWritePermission {
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
            } else {
                Text("Ask your group admin to add items")
                    .font(.monaco(AppTheme.ElderTypography.caption))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
            }
            
            Spacer()
        }
    }
    
    private func loadDataWithRefreshCheck() async {
        // Check if we need to refresh based on 3600-second interval
        let lastRefresh = Date(timeIntervalSince1970: lastRefreshTimestamp)
        let timeSinceRefresh = Date().timeIntervalSince(lastRefresh)
        
        if timeSinceRefresh >= refreshInterval {
            // It's been more than 1 hour, do refresh
            print("⏰ Auto-refresh triggered (last refresh: \(Int(timeSinceRefresh)) seconds ago)")
            await performDataRefresh()
        } else if !hasLoadedData {
            // First load for this session
            print("📱 Initial data load for session")
            await performDataRefresh()
        } else {
            // Skip refresh - not needed yet
            let timeUntilRefresh = refreshInterval - timeSinceRefresh
            print("⏭️ Skipping refresh - last refresh was \(Int(timeSinceRefresh)) seconds ago")
            print("   Next auto-refresh in \(Int(timeUntilRefresh)) seconds")
        }
    }
    
    private func forceRefreshData() async {
        // Manual refresh - bypasses timer
        print("👤 Manual refresh requested")
        await performDataRefresh()
    }
    
    private func performDataRefresh() async {
        // Prevent concurrent loads
        guard !isLoadingData else {
            print("⏭️ Already loading data, skipping duplicate request")
            return
        }
        
        isLoadingData = true
        defer { 
            isLoadingData = false
            lastRefreshTimestamp = Date().timeIntervalSince1970
        }
        
        print("🔍 DEBUG: MyHealthDashboardView loading data...")
        print("   Current group: \(FirebaseGroupService.shared.currentGroup?.name ?? "NO GROUP")")
        print("   User has write permission: \(groupService.userHasWritePermission)")
        
        // Force refresh to bypass cache
        await viewModel.loadData(forceRefresh: true)
        selectedPeriods = [viewModel.currentPeriod]
        hasLoadedData = true
        
        print("🔍 DEBUG: Loaded \(viewModel.allItems.count) items")
        
        // Update badge and notifications as before
        await BadgeManager.shared.updateBadgeForCurrentPeriod()
    }
    
    private func setupRefreshTimer() {
        // Cancel existing timer if any
        refreshTimer?.invalidate()
        
        // Setup timer to fire once every hour (3600 seconds)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor in
                print("⏰ Hourly refresh timer fired")
                await performDataRefresh()
            }
        }
        
        print("⏰ Scheduled periodic refresh every \(Int(refreshInterval)) seconds")
    }
    
    private var addButton: some View {
        Button(action: { 
            if !groupService.userHasWritePermission && groupService.currentGroup != nil {
                showNoPermissionAlert = true
            } else {
                showAddItem = true
            }
        }) {
            Image(systemName: "plus")
                .font(.system(size: AppTheme.Typography.headline))
                .foregroundColor(groupService.userHasWritePermission ? AppTheme.Colors.primaryBlue : Color.gray)
        }
        .frame(
            minWidth: AppTheme.Dimensions.minimumTouchTarget,
            minHeight: AppTheme.Dimensions.minimumTouchTarget
        )
        .accessibilityLabel("Add new health item")
        .accessibilityHint(groupService.userHasWritePermission ? "Opens form to add medication, supplement, or diet item" : "You don't have permission to add items")
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
    
    private func deleteMedication(_ medication: Medication) async {
        do {
            // Delete from Core Data first
            try await CoreDataManager.shared.deleteMedication(medication.id)
            
            // Delete from Firebase if in a group
            if FirebaseGroupService.shared.currentGroup != nil {
                try await groupDataService.deleteMedication(medication.id.uuidString)
            }
            
            // Refresh the view
            await viewModel.loadData(forceRefresh: true)
            
            // Update notifications
            await MedicationNotificationScheduler.shared.scheduleDailyNotifications()
        } catch {
            print("Error deleting medication: \(error)")
        }
    }
    
    private func handleItemTap(_ item: any HealthItem) {
        #if DEBUG
        print("Tapped item: \(item.name)")
        #endif
        
        // Navigate to detail view for medications
        if let medication = item as? Medication {
            selectedMedication = medication
            showMedicationDetail = true
        }
        
        // Donate to Spotlight for better search and predictions
        donateToSpotlight(item: item)
    }
    
    private func handleMarkTaken(_ itemData: (item: any HealthItem, dose: ScheduledDose?)) {
        // Check permissions first
        if !groupService.userHasWritePermission && groupService.currentGroup != nil {
            showNoPermissionAlert = true
            return
        }
        
        guard let dose = itemData.dose else { return }
        
        Task {
            await viewModel.markDoseTaken(
                itemId: itemData.item.id, 
                doseId: dose.id,
                firebaseDoseId: dose.firebaseDoseId
            )
        }
    }
    
    private func confirmMarkTaken(_ itemData: (item: any HealthItem, dose: ScheduledDose?)) {
        guard let dose = itemData.dose else { 
            print("⚠️ No dose to mark as taken")
            return 
        }
        
        Task { @MainActor in
            print("✅ Marking dose as taken for: \(itemData.item.name)")
            await viewModel.markDoseTaken(
                itemId: itemData.item.id, 
                doseId: dose.id,
                firebaseDoseId: dose.firebaseDoseId
            )
            
            // Clear UI state
            pendingDoseToMark = nil
            tappedItemId = nil // Clear visual feedback
            
            // Force a refresh to ensure UI updates
            await viewModel.loadData(forceRefresh: true)
            
            // Update badge count based on remaining items
            await updateBadgeCount()
        }
    }
    
    private func updateBadgeCount() async {
        // Use BadgeManager to update badge after medication is taken
        // This will recalculate based on remaining untaken medications
        await BadgeManager.shared.updateAfterMedicationTaken()
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
    
    private let dataProcessor = HealthDataProcessor.shared
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
    
    func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        
        do {
            // Use the singleton's caching mechanism
            let processedData = try await dataProcessor.getHealthData(forceRefresh: forceRefresh)
            allItems = processedData.items
            periodCounts = processedData.periodCounts
            isLoading = false
        } catch {
            self.error = error as? AppError ?? AppError.coreDataFetchFailed
            isLoading = false
        }
    }
    
    func markDoseTaken(itemId: UUID, doseId: UUID, firebaseDoseId: String? = nil) async {
        do {
            print("📝 MyHealthDashboardViewModel: Marking dose as taken...")
            let processedData = try await dataProcessor.markDoseTakenAndRefresh(
                itemId: itemId,
                doseId: doseId,
                firebaseDoseId: firebaseDoseId
            )
            
            // Update the UI on main thread
            await MainActor.run {
                self.allItems = processedData.items
                self.periodCounts = processedData.periodCounts
                print("✅ UI updated with new dose status")
            }
        } catch {
            print("❌ Error marking dose as taken: \(error)")
            await MainActor.run {
                self.error = error as? AppError ?? AppError.coreDataSaveFailed
            }
        }
    }
}

// MARK: - Preview
#Preview {
    MyHealthDashboardView()
}
