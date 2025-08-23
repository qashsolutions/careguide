//
//  TrialPaymentPromptView.swift
//  HealthGuide
//
//  Payment prompt shown on days 12-14 of free trial
//  Encourages users to add payment before trial ends
//

import SwiftUI
import StoreKit

@available(iOS 18.0, *)
struct TrialPaymentPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [AppTheme.Colors.primaryBlue.opacity(0.05), AppTheme.Colors.backgroundSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Header with urgency
                        VStack(spacing: 16) {
                            // Trial days remaining badge
                            HStack {
                                Image(systemName: "clock.fill")
                                Text("\(subscriptionManager.trialDaysRemaining) days left in trial")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                            
                            Text("Don't Lose Your Progress!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text("Add payment now to ensure uninterrupted access when your trial ends")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)
                        
                        // What happens after trial
                        VStack(alignment: .leading, spacing: 20) {
                            Text("After your trial ends:")
                                .font(.headline)
                            
                            ComparisonRow(
                                icon: "checkmark.circle.fill",
                                iconColor: .green,
                                title: "With Premium",
                                description: "Continue with unlimited access to all features"
                            )
                            
                            ComparisonRow(
                                icon: "xmark.circle.fill",
                                iconColor: .red,
                                title: "Without Premium",
                                description: "Limited to once-per-day access, no document uploads"
                            )
                        }
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(16)
                        .padding(.horizontal)
                        
                        // Features reminder
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Keep enjoying these premium features:")
                                .font(.headline)
                            
                            ForEach(premiumFeatures, id: \.self) { feature in
                                HStack(spacing: 12) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(AppTheme.Colors.primaryBlue)
                                    Text(feature)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Payment info
                        VStack(spacing: 12) {
                            Text("Just $8.99/month")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("No charge until your trial ends")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Cancel anytime before day 7")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(AppTheme.Colors.primaryBlue.opacity(0.1))
                        .cornerRadius(12)
                        
                        // Action buttons
                        VStack(spacing: 16) {
                            // Add payment button
                            Button(action: addPayment) {
                                HStack {
                                    if isPurchasing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "creditcard.fill")
                                        Text("Add Payment Method")
                                    }
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
                            .disabled(isPurchasing)
                            .padding(.horizontal)
                            
                            // Remind me later
                            Button(action: remindLater) {
                                Text("Remind me tomorrow")
                                    .foregroundColor(AppTheme.Colors.primaryBlue)
                            }
                        }
                        .padding(.bottom, 50)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: skipForNow) {
                        Text("Skip")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: subscriptionManager.subscriptionState) { _, newState in
            // Dismiss if payment was successful
            if case .active = newState {
                dismiss()
            }
        }
        .onAppear {
            subscriptionManager.markPaymentPromptSeen()
        }
    }
    
    // MARK: - Actions
    
    private func addPayment() {
        isPurchasing = true
        
        Task {
            do {
                try await subscriptionManager.purchase()
                // Success handled by onChange
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isPurchasing = false
            }
        }
    }
    
    private func remindLater() {
        // Schedule reminder for tomorrow
        Task {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            await NotificationManager.shared.schedulePaymentPromptReminder(date: tomorrow)
        }
        dismiss()
    }
    
    private func skipForNow() {
        dismiss()
    }
    
    // MARK: - Data
    
    private let premiumFeatures = [
        "Unlimited daily access",
        "Upload medical documents",
        "Advanced health analytics",
        "Family member profiles",
        "Cloud sync across devices"
    ]
}

// MARK: - Comparison Row

@available(iOS 18.0, *)
struct ComparisonRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    TrialPaymentPromptView()
}