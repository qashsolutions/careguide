//
//  DailyAccessLockView.swift
//  HealthGuide
//
//  Lock screen shown when basic users have used their daily access
//  Displays countdown and upgrade options
//

import SwiftUI
import StoreKit

@available(iOS 18.0, *)
struct DailyAccessLockView: View {
    @StateObject private var accessManager = AccessSessionManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingUpgradeSheet = false
    @State private var showingWhyLimitSheet = false
    @State private var timeString = ""
    
    // Timer for countdown
    @State private var countdownTimer: Timer?
    
    var body: some View {
        ZStack {
            // OPTIMIZED: Using static image-based gradient for better performance
            // LinearGradient causes continuous GPU rendering and high energy usage
            Rectangle()
                .fill(AppTheme.Colors.backgroundSecondary)
                .overlay(
                    AppTheme.Colors.primaryBlue.opacity(0.03)
                        .ignoresSafeArea()
                )
            
            VStack(spacing: 30) {
                Spacer()
                
                // Lock icon
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                    // REMOVED: .symbolEffect(.pulse) - was causing continuous animation and high energy usage
                
                // Main message
                VStack(spacing: 12) {
                    Text(mainTitle)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(mainMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Countdown display
                VStack(spacing: 8) {
                    Text("Next free access in:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(timeString)
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .monospacedDigit()
                }
                .padding(.vertical)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Upgrade button
                    Button(action: { showingUpgradeSheet = true }) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Upgrade to Premium")
                            Text("$8.99/mo")
                                .fontWeight(.regular)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [AppTheme.Colors.primaryBlue, AppTheme.Colors.primaryBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    
                    // Why this limit button
                    Button(action: { showingWhyLimitSheet = true }) {
                        Text("Why this limit?")
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .underline()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // DISABLED TIMER: Only update time string once on appear to reduce energy usage
            updateTimeString()
            // startCountdown() - disabled to eliminate all timer-based updates
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
        .sheet(isPresented: $showingUpgradeSheet) {
            UpgradeView()
        }
        .sheet(isPresented: $showingWhyLimitSheet) {
            WhyLimitView()
        }
    }
    
    // MARK: - Helper Methods
    
    private var mainTitle: String {
        // Check if user's trial has expired
        if UserDefaults.standard.bool(forKey: "hasUsedTrial") && 
           !subscriptionManager.subscriptionState.isActive && 
           !subscriptionManager.subscriptionState.isInTrial {
            return "Trial Ended"
        }
        return "Daily Access Used"
    }
    
    private var mainMessage: String {
        // Check if user's trial has expired
        if UserDefaults.standard.bool(forKey: "hasUsedTrial") && 
           !subscriptionManager.subscriptionState.isActive && 
           !subscriptionManager.subscriptionState.isInTrial {
            return "Your 7-day free trial has ended. Subscribe to continue enjoying unlimited access"
        }
        return "Come back tomorrow or upgrade for unlimited access"
    }
    
    private func startCountdown() {
        updateTimeString()
        
        // OPTIMIZED: Update only once per hour to minimize energy usage
        // Display shows hours anyway, so hourly updates are sufficient
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                updateTimeString()
                
                // Check if it's a new day (within 1 hour window is acceptable)
                if accessManager.timeUntilNextAccess <= 0 {
                    await accessManager.checkAccess(subscriptionState: nil)
                    countdownTimer?.invalidate()
                }
            }
        }
    }
    
    private func updateTimeString() {
        let totalSeconds = Int(accessManager.timeUntilNextAccess)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        // OPTIMIZED: Show only hours and minutes, no seconds to reduce frequent UI updates
        if hours > 0 {
            timeString = String(format: "%d hr %d min", hours, minutes)
        } else if minutes > 0 {
            timeString = String(format: "%d min", minutes)
        } else {
            timeString = "Less than 1 minute"
        }
    }
}

// MARK: - Upgrade View

@available(iOS 18.0, *)
struct UpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(AppTheme.Colors.primaryBlue)
                            .symbolEffect(.bounce)
                        
                        Text("Premium Subscription")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Unlock unlimited access and all features")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)
                    
                    // Benefits list
                    VStack(alignment: .leading, spacing: 20) {
                        BenefitRow(icon: "infinity", text: "Unlimited daily access")
                        BenefitRow(icon: "doc.badge.plus", text: "Upload medical documents")
                        BenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Advanced analytics")
                        BenefitRow(icon: "person.3.fill", text: "Family sharing")
                        BenefitRow(icon: "icloud.fill", text: "Cloud sync across devices")
                        BenefitRow(icon: "headphones", text: "Priority support")
                    }
                    .padding(.horizontal)
                    
                    // Pricing
                    VStack(spacing: 8) {
                        Text("7-day free trial")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        Text("then $8.99 per month")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Cancel anytime in Settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Subscribe button
                    Button(action: subscribe) {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Start Free Trial")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.Colors.primaryBlue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                    .disabled(isPurchasing)
                    .padding(.horizontal)
                    
                    // Legal text
                    VStack(spacing: 8) {
                        Button("Restore Purchases") {
                            Task {
                                await restorePurchases()
                            }
                        }
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        
                        Link("Privacy Policy", destination: URL(string: "https://careguide.app/privacy")!)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Link("Terms of Use", destination: URL(string: "https://careguide.app/terms")!)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .padding(.vertical)
                }
                .padding(.bottom, 50)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: subscriptionManager.subscriptionState.isActive) { _, isActive in
            if isActive {
                dismiss()
            }
        }
    }
    
    // MARK: - Actions
    
    private func subscribe() {
        isPurchasing = true
        
        Task {
            do {
                try await subscriptionManager.purchase()
                // After purchase, explicitly check subscription status
                await subscriptionManager.checkSubscriptionStatus()
                // If subscription is now active, dismiss the view
                if subscriptionManager.subscriptionState.isActive {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isPurchasing = false
            }
        }
    }
    
    private func restorePurchases() async {
        isPurchasing = true
        
        do {
            try await subscriptionManager.restorePurchases()
            if !subscriptionManager.subscriptionState.isActive {
                errorMessage = "No active subscriptions found"
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isPurchasing = false
    }
}

// MARK: - Benefit Row

@available(iOS 18.0, *)
struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppTheme.Colors.primaryBlue)
                .frame(width: 30)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

// MARK: - Why Limit View

@available(iOS 18.0, *)
struct WhyLimitView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why Once Per Day?")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("We believe in making health tracking accessible to everyone")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Explanation sections
                    VStack(alignment: .leading, spacing: 20) {
                        ExplanationSection(
                            icon: "heart.fill",
                            title: "Perfect for Daily Routines",
                            description: "Most people take medications at specific times each day. Our free tier lets you track your morning, lunch, or evening medications without cost."
                        )
                        
                        ExplanationSection(
                            icon: "dollarsign.circle.fill",
                            title: "Sustainable for Everyone",
                            description: "This model helps us maintain a free tier while offering premium features to those who need more frequent access."
                        )
                        
                        ExplanationSection(
                            icon: "person.2.fill",
                            title: "Supporting Development",
                            description: "Premium subscriptions help us continuously improve the app, add new features, and provide support to all users."
                        )
                        
                        ExplanationSection(
                            icon: "lock.shield.fill",
                            title: "Your Data, Protected",
                            description: "Whether free or premium, your health data is encrypted and secure. We never sell or share your information."
                        )
                    }
                    
                    // Call to action
                    VStack(spacing: 16) {
                        Text("Need more access?")
                            .font(.headline)
                        
                        Text("Try Premium free for 7 days and see if unlimited access works better for your needs.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: { dismiss() }) {
                            Text("Upgrade to Premium")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppTheme.Colors.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                    .cornerRadius(16)
                    .padding(.top)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Explanation Section

@available(iOS 18.0, *)
struct ExplanationSection: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(AppTheme.Colors.primaryBlue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DailyAccessLockView()
}