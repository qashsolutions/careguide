//
//  CareMemosView.swift
//  HealthGuide
//
//  Audio memo recording and playback for caregivers
//  Production-ready with 10 memo limit and single player constraint
//

import SwiftUI
import AVFoundation

@available(iOS 18.0, *)
struct CareMemosView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var viewModel = CareMemosViewModel()
    
    @State private var showingDeleteAlert = false
    @State private var memoToDelete: CareMemo?
    @State private var recordingStartTime: Date?
    @State private var showingTitleDialog = false
    @State private var memoTitle = ""
    @State private var pendingRecordingResult: (url: URL, duration: TimeInterval)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "F8F8F8"),
                        Color(hex: "FAFAFA")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Recording section
                    recordingSection
                        .padding(.horizontal, AppTheme.Spacing.screenPadding)
                        .padding(.vertical, AppTheme.Spacing.large)
                    
                    Divider()
                    
                    // Memos list
                    if viewModel.isLoading {
                        Spacer()
                        ProgressView("Loading memos...")
                        Spacer()
                    } else if viewModel.memos.isEmpty {
                        emptyStateView
                    } else {
                        memosList
                    }
                    
                    // Memo count indicator
                    memoCountIndicator
                        .padding(.bottom, AppTheme.Spacing.medium)
                }
            }
            .navigationTitle("Memos")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadMemos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .careMemoDataDidChange)) { _ in
                Task {
                    await viewModel.loadMemos()
                }
            }
            .alert("Delete Memo?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let memo = memoToDelete {
                        Task {
                            await viewModel.deleteMemo(memo)
                        }
                    }
                }
            } message: {
                Text("This audio memo will be permanently deleted.")
            }
            .alert("Add a quick note?", isPresented: $showingTitleDialog) {
                TextField("e.g., Morning medicine", text: $memoTitle)
                    .onChange(of: memoTitle) { _, newValue in
                        // Limit to 3 words
                        let words = newValue.split(separator: " ")
                        if words.count > 3 {
                            memoTitle = words.prefix(3).joined(separator: " ")
                        }
                    }
                Button("Save with note") {
                    saveMemoWithTitle(title: memoTitle.isEmpty ? nil : memoTitle)
                }
                Button("Skip", role: .cancel) {
                    saveMemoWithTitle(title: nil)
                }
            } message: {
                Text("Optional: Add up to 3 words to identify this memo")
            }
            .onDisappear {
                // Clean up audio resources when leaving the view
                if audioManager.isRecording {
                    stopRecording()
                }
                audioManager.cleanup()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    // Stop recording and cleanup when app goes to background
                    if audioManager.isRecording {
                        stopRecording()
                    }
                    audioManager.cleanup()
                }
            }
            .onChange(of: audioManager.lastRecordingResult) { _, newResult in
                // Handle auto-stop when recording reaches max duration
                if let result = newResult {
                    audioManager.isRecording = false
                    
                    if let url = result.url {
                        // Store the result and show title dialog
                        pendingRecordingResult = (url: url, duration: result.duration)
                        memoTitle = ""
                        showingTitleDialog = true
                    }
                    
                    // Clear the result after handling
                    audioManager.lastRecordingResult = nil
                }
            }
        }
    }
    
    // MARK: - Recording Section
    private var recordingSection: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Record button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(audioManager.isRecording ? AppTheme.Colors.errorRed : AppTheme.Colors.primaryBlue)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: audioManager.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .disabled(viewModel.memoCount >= 10 && !audioManager.isRecording)
            .scaleEffect(audioManager.isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: audioManager.isRecording)
            
            // Recording status
            if audioManager.isRecording {
                VStack(spacing: AppTheme.Spacing.small) {
                    Text("Recording...")
                        .font(.monaco(AppTheme.ElderTypography.body))
                        .foregroundColor(AppTheme.Colors.errorRed)
                    
                    Text(formatTime(audioManager.recordingTime))
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Text("Max 1 minute")
                        .font(.monaco(AppTheme.ElderTypography.body))  // Increased font size
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .bold()  // Make it more visible
                }
            } else {
                Text(viewModel.memoCount >= 10 ? "Memo limit reached (10/10)" : "Tap to record a memo")
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(viewModel.memoCount >= 10 ? AppTheme.Colors.errorRed : AppTheme.Colors.textSecondary)
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: AppTheme.Spacing.xxLarge) {
            Spacer()
            
            Image(systemName: "mic.circle")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text("No Memos Yet")
                .font(.monaco(AppTheme.ElderTypography.title))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text("Record important observations about medications and care")
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
            
            Spacer()
        }
    }
    
    // MARK: - Memos List
    private var memosList: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.small) {
                ForEach(groupedMemos, id: \.key) { date, memos in
                    Section {
                        ForEach(memos) { memo in
                            MemoRow(
                                memo: memo,
                                isPlaying: audioManager.currentlyPlayingId == memo.id,
                                onPlay: {
                                    playMemo(memo)
                                },
                                onDelete: {
                                    memoToDelete = memo
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text(formatSectionDate(date))
                                .font(.monaco(AppTheme.ElderTypography.footnote))
                                .foregroundColor(AppTheme.Colors.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.Spacing.medium)
                        .padding(.top, AppTheme.Spacing.small)
                    }
                }
            }
            .padding(AppTheme.Spacing.screenPadding)
        }
    }
    
    // MARK: - Memo Count Indicator
    private var memoCountIndicator: some View {
        HStack {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(index < viewModel.memoCount ? AppTheme.Colors.primaryBlue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Grouped Memos
    private var groupedMemos: [(key: Date, value: [CareMemo])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.memos) { memo in
            calendar.startOfDay(for: memo.recordedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    // MARK: - Actions
    private func toggleRecording() {
        if audioManager.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        print("🧵 [CareMemosView] startRecording called on thread: \(Thread.current)")
        print("🧵 [CareMemosView] Is Main Thread: \(Thread.isMainThread)")
        
        Task { @MainActor in
            do {
                print("🧵 [CareMemosView] Inside Task - Actor: @MainActor")
                recordingStartTime = Date()
                _ = try await audioManager.startRecording()
                // AudioManager sets isRecording = true internally
            } catch {
                print("❌ Failed to start recording: \(error)")
            }
        }
    }
    
    private func stopRecording() {
        guard audioManager.isRecording else { return }
        print("🧵 [CareMemosView] stopRecording called on thread: \(Thread.current)")
        print("🧵 [CareMemosView] Is Main Thread: \(Thread.isMainThread)")
        
        let result = audioManager.stopRecording()
        
        if let url = result.url {
            // Store the result and show title dialog
            pendingRecordingResult = (url: url, duration: result.duration)
            memoTitle = ""
            showingTitleDialog = true
        }
        // AudioManager sets isRecording = false internally
    }
    
    private func playMemo(_ memo: CareMemo) {
        if audioManager.currentlyPlayingId == memo.id {
            audioManager.stopPlayback()
        } else {
            if let url = memo.fileURL {
                do {
                    try audioManager.play(url: url, memoId: memo.id)
                } catch {
                    print("Failed to play memo: \(error)")
                }
            }
        }
    }
    
    // MARK: - Formatters
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Save Memo with Title
    private func saveMemoWithTitle(title: String?) {
        guard let pending = pendingRecordingResult else { return }
        
        let memo = CareMemo(
            audioFileURL: pending.url.absoluteString,
            duration: pending.duration,
            recordedAt: recordingStartTime ?? Date(),
            title: title
        )
        
        Task {
            await viewModel.saveMemo(memo)
        }
        
        // Clear pending result
        pendingRecordingResult = nil
        recordingStartTime = nil
    }
}

// MARK: - Memo Row
@available(iOS 18.0, *)
struct MemoRow: View {
    let memo: CareMemo
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            // Play button
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(isPlaying ? AppTheme.Colors.primaryBlue : Color.gray)
            }
            
            // Memo info
            VStack(alignment: .leading, spacing: 4) {
                // Title if available (e.g., "Blood pressure check")
                if let title = memo.title, !title.isEmpty {
                    Text(title)
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                }
                
                // Date and Time (e.g., "8:21 PM")
                Text(formatDateTime())
                    .font(.monaco(AppTheme.ElderTypography.body))
                    .foregroundColor(memo.title == nil ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                
                // Duration (e.g., "0:45")
                Text(memo.formattedDuration)
                    .font(.monaco(AppTheme.ElderTypography.footnote))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.Colors.errorRed)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
    
    private func formatDateTime() -> String {
        let formatter = DateFormatter()
        // Force US locale to ensure 12-hour format with AM/PM
        formatter.locale = Locale(identifier: "en_US")
        
        // Check if it's today
        let calendar = Calendar.current
        if calendar.isDateInToday(memo.recordedAt) {
            // For today, just show time (e.g., "8:21 PM")
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(memo.recordedAt) {
            // For yesterday, show "Yesterday, 8:21 PM"
            formatter.dateFormat = "'Yesterday,' h:mm a"
        } else {
            // For other dates, show "Dec 10, 8:21 PM"
            formatter.dateFormat = "MMM d, h:mm a"
        }
        
        return formatter.string(from: memo.recordedAt)
    }
}

// MARK: - View Model
@available(iOS 18.0, *)
@MainActor
final class CareMemosViewModel: ObservableObject {
    @Published var memos: [CareMemo] = []
    @Published var isLoading = false
    @Published var memoCount = 0
    
    private let coreDataManager = CoreDataManager.shared
    
    func loadMemos() async {
        isLoading = true
        do {
            memos = try await coreDataManager.fetchCareMemos()
            memoCount = memos.count
        } catch {
            print("Failed to load memos: \(error)")
        }
        isLoading = false
    }
    
    func saveMemo(_ memo: CareMemo) async {
        print("🧵 [ViewModel] saveMemo called")
        print("🧵 [ViewModel] Actor context: async function")
        
        do {
            try await coreDataManager.saveCareMemo(memo)
            // Don't call loadMemos() here - the notification will trigger it
            print("✅ Memo saved successfully")
        } catch {
            print("❌ Failed to save memo: \(error)")
        }
    }
    
    func deleteMemo(_ memo: CareMemo) async {
        do {
            try await coreDataManager.deleteCareMemo(memo.id)
            await loadMemos()
        } catch {
            print("Failed to delete memo: \(error)")
        }
    }
}
