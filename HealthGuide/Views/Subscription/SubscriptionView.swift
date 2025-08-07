//
//  SubscriptionView.swift
//  HealthGuide
//
//  Subscription management UI with trial, payment, and cancellation
//  Production-ready with clear pricing and refund information
//

import SwiftUI
import StoreKit

@available(iOS 18.0, *)
struct SubscriptionView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showPaymentOptions = false
    @State private var showCancellationConfirmation = false
    @State private var cancellationResult: CancellationResult?
    @State private var selectedPaymentMethod: SubscriptionManager.PaymentMethod = .applePay
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [Color(hex: "F8F8F8"), Color(hex: "FAFAFA")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppTheme.Spacing.large) {
                        // Current status card
                        statusCard
                        
                        // Pricing information
                        pricingCard
                        
                        // Features list
                        featuresCard
                        
                        // Action button
                        actionButton
                        
                        // Cancellation/refund info
                        if subscriptionManager.subscriptionState.isActive {
                            cancellationInfoCard
                        }
                    }
                    .padding(AppTheme.Spacing.screenPadding)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryBlue)
                }
            }
            .sheet(isPresented: $showPaymentOptions) {
                // STRIPE PAYMENT SELECTOR DISABLED
                // Apple requires using In-App Purchases for digital subscriptions
                // Direct Apple Pay purchase without payment method selection
                EmptyView()
                    .task {
                        showPaymentOptions = false
                        do {
                            // Always use Apple Pay (StoreKit) for digital subscriptions
                            try await subscriptionManager.purchaseSubscription(method: .applePay)
                        } catch {
                            print("Purchase failed: \(error)")
                        }
                    }
                
                /* PAYMENT METHOD SELECTOR DISABLED - Apple IAP Required
                PaymentMethodSelector(
                    selectedMethod: $selectedPaymentMethod,
                    onPurchase: {
                        Task {
                            try await subscriptionManager.purchaseSubscription(method: selectedPaymentMethod)
                        }
                    }
                )
                */
            }
            .alert("Cancel Subscription", isPresented: $showCancellationConfirmation) {
                Button("Cancel Subscription", role: .destructive) {
                    Task {
                        await processCancellation()
                    }
                }
                Button("Keep Subscription", role: .cancel) { }
            } message: {
                Text(getCancellationMessage())
            }
            .alert("Cancellation Complete", isPresented: .constant(cancellationResult != nil)) {
                Button("OK") {
                    cancellationResult = nil
                }
            } message: {
                if let result = cancellationResult {
                    Text(getCancellationResultMessage(result))
                }
            }
            .task {
                await subscriptionManager.loadProducts()
                await subscriptionManager.checkSubscriptionStatus()
            }
        }
    }
    
    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Current Status")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Text(subscriptionManager.subscriptionState.displayName)
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(statusColor)
                }
                
                Spacer()
                
                Image(systemName: statusIcon)
                    .font(.system(size: 36))
                    .foregroundColor(statusColor)
            }
            
            // Additional status info
            statusDetails
        }
        .padding(AppTheme.Spacing.large)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private var statusDetails: some View {
        switch subscriptionManager.subscriptionState {
        case .trial(let startDate, let endDate):
            VStack(spacing: AppTheme.Spacing.small) {
                let totalDays = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 7
                let daysElapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
                let daysRemaining = max(0, totalDays - daysElapsed)
                
                ProgressView(value: Double(daysElapsed), total: Double(totalDays))
                    .tint(AppTheme.Colors.primaryBlue)
                
                VStack(spacing: 2) {
                    Text("\(daysRemaining) days remaining in free trial")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Text("Started on \(startDate, formatter: dateFormatter)")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.8))
                }
            }
            
        case .active(let expiryDate, let autoRenew):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                if autoRenew {
                    Text("Next billing date: \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    Text("Expires on: \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.monaco(AppTheme.ElderTypography.footnote))
            .foregroundColor(AppTheme.Colors.textSecondary)
            
        case .cancelled(let accessUntilDate, _):
            Text("Access until: \(accessUntilDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.monaco(AppTheme.ElderTypography.footnote))
                .foregroundColor(AppTheme.Colors.warningOrange)
            
        default:
            EmptyView()
        }
    }
    
    // MARK: - Pricing Card
    private var pricingCard: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Text("Monthly Plan")
                        .font(.monaco(AppTheme.ElderTypography.headline))
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        Text("$")
                            .font(.monaco(AppTheme.ElderTypography.body))
                        Text("8.99")
                            .font(.monaco(AppTheme.ElderTypography.title))
                            .fontWeight(.bold)
                        Text("/month")
                            .font(.monaco(AppTheme.ElderTypography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xSmall) {
                    Label("7-day free trial", systemImage: "checkmark.circle.fill")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.successGreen)
                    
                    Text("Then $8.99/month")
                        .font(.monaco(AppTheme.ElderTypography.footnote))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(
            LinearGradient(
                colors: [AppTheme.Colors.primaryBlue.opacity(0.05), AppTheme.Colors.primaryBlue.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                .stroke(AppTheme.Colors.primaryBlue.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
    
    // MARK: - Features Card
    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Premium Features")
                .font(.monaco(AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                FeatureRow(icon: "infinity", text: "Unlimited daily access", color: AppTheme.Colors.primaryBlue)
                FeatureRow(icon: "person.3.fill", text: "Unlimited group members", color: AppTheme.Colors.primaryBlue)
                FeatureRow(icon: "doc.text.fill", text: "Upload & download documents", color: .green)
                FeatureRow(icon: "bell.badge.fill", text: "Advanced reminders", color: .orange)
                FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Health analytics", color: AppTheme.Colors.primaryBlue)
                FeatureRow(icon: "lock.shield.fill", text: "Enhanced security", color: .red)
                FeatureRow(icon: "headphones", text: "Priority support", color: .indigo)
            }
            
            // Basic plan limitations
            if !subscriptionManager.subscriptionState.isActive {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    Divider().padding(.vertical, AppTheme.Spacing.small)
                    
                    Text("Basic Plan (Free)")
                        .font(.monaco(AppTheme.ElderTypography.caption))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(AppTheme.Colors.warningOrange)
                        Text("Limited to once-per-day access")
                            .font(.monaco(AppTheme.ElderTypography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(AppTheme.Colors.warningOrange)
                        Text("Cannot upload or download documents")
                            .font(.monaco(AppTheme.ElderTypography.footnote))
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.large)
        .background(Color.white)
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Cancellation Info Card
    private var cancellationInfoCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Label("Cancellation Policy", systemImage: "info.circle")
                .font(.monaco(AppTheme.ElderTypography.headline))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Text("• Days 1-7: Free trial")
                Text("• Days 8-14: Cancel for 50% refund")
                Text("• Days 15+: No refund, access until day 31")
                Text("• No questions asked")
            }
            .font(.monaco(AppTheme.ElderTypography.footnote))
            .foregroundColor(AppTheme.Colors.textSecondary)
        }
        .padding(AppTheme.Spacing.large)
        .background(Color(hex: "FFF9E6"))
        .cornerRadius(AppTheme.Dimensions.cardCornerRadius)
    }
    
    // MARK: - Action Button
    @ViewBuilder
    private var actionButton: some View {
        switch subscriptionManager.subscriptionState {
        case .none, .expired:
            Button(action: { 
                Task {
                    await subscriptionManager.startFreeTrial()
                }
            }) {
                Text("Start 7-Day Free Trial")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .background(AppTheme.Colors.primaryBlue)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            }
            
        case .trial:
            Button(action: { showPaymentOptions = true }) {
                Text("Upgrade Now")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .background(AppTheme.Colors.successGreen)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            }
            
        case .active:
            Button(action: { showCancellationConfirmation = true }) {
                Text("Cancel Subscription")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .background(Color.white)
                    .foregroundColor(AppTheme.Colors.errorRed)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                            .stroke(AppTheme.Colors.errorRed, lineWidth: 2)
                    )
            }
            
        case .cancelled:
            Button(action: { showPaymentOptions = true }) {
                Text("Resubscribe")
                    .font(.monaco(AppTheme.ElderTypography.callout))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Dimensions.elderButtonHeight)
                    .background(AppTheme.Colors.primaryBlue)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.Dimensions.buttonCornerRadius)
            }
            
        default:
            EmptyView()
        }
    }
    
    // MARK: - Helper Properties
    private var statusColor: Color {
        switch subscriptionManager.subscriptionState {
        case .active, .trial:
            return AppTheme.Colors.successGreen
        case .cancelled, .gracePeriod:
            return AppTheme.Colors.warningOrange
        case .expired, .none:
            return AppTheme.Colors.errorRed
        case .loading:
            return AppTheme.Colors.textSecondary
        }
    }
    
    private var statusIcon: String {
        switch subscriptionManager.subscriptionState {
        case .active, .trial:
            return "checkmark.circle.fill"
        case .cancelled:
            return "exclamationmark.circle.fill"
        case .expired, .none:
            return "xmark.circle.fill"
        case .gracePeriod:
            return "clock.fill"
        case .loading:
            return "arrow.clockwise"
        }
    }
    
    // MARK: - Helper Methods
    private func getCancellationMessage() -> String {
        let daysSinceStart = Calendar.current.dateComponents([.day], 
            from: UserDefaults.standard.object(forKey: "subscription.startDate") as? Date ?? Date(),
            to: Date()
        ).day ?? 0
        
        if daysSinceStart >= 8 && daysSinceStart <= 14 {
            return "You're within days 8-14 of your subscription. You'll receive a 50% refund ($4.50) and keep access for 15 more days."
        } else if daysSinceStart >= 15 {
            return "You'll keep access until the end of your billing period (day 31). No refund will be issued after 14 days."
        } else {
            return "You're still in your free trial period. No charges have been made yet."
        }
    }
    
    private func getCancellationResultMessage(_ result: CancellationResult) -> String {
        switch result.refundPolicy {
        case .firstTime:
            if result.refundAmount > 0 {
                return "Your subscription has been cancelled. As a first-time cancellation, you'll receive a 50% refund ($\(result.refundAmount)) within 5-10 business days. You have 48 hours to export your data (until \(result.accessUntilDate.formatted(date: .abbreviated, time: .omitted)))."
            }
        case .secondTime:
            return "Your subscription has been cancelled. You've previously used your one-time refund, so no refund will be issued. However, you can continue using the app until \(result.accessUntilDate.formatted(date: .abbreviated, time: .omitted))."
        case .blocked:
            return "Your subscription has been cancelled. Based on your subscription history, no refund is available. Access will end on \(result.accessUntilDate.formatted(date: .abbreviated, time: .omitted))."
        }
        
        // Default for outside refund window
        return "Your subscription has been cancelled. You can continue using the app until \(result.accessUntilDate.formatted(date: .abbreviated, time: .omitted))."
    }
    
    private func processCancellation() async {
        do {
            cancellationResult = try await subscriptionManager.cancelSubscription()
        } catch {
            // Handle error
            print("Cancellation failed: \(error)")
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 28)
            
            Text(text)
                .font(.monaco(AppTheme.ElderTypography.body))
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Spacer()
        }
    }
}