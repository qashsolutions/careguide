//
//  TrialStatusModal.swift
//  HealthGuide
//
//  Shows trial status with days remaining and subscription option
//  Displays daily to keep users informed and allow payment testing
//

import SwiftUI
import StoreKit

@available(iOS 18.0, *)
struct TrialStatusModal: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var cloudTrialManager = CloudTrialManager.shared
    @Binding var isPresented: Bool
    
    @State private var isProcessingPayment = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Computed properties for trial state
    private var trialState: CloudTrialManager.UnifiedTrialState? {
        cloudTrialManager.trialState
    }
    
    private var daysRemaining: Int {
        trialState?.daysRemaining ?? 0
    }
    
    private var daysUsed: Int {
        trialState?.daysUsed ?? 0
    }
    
    private var isLastTwoDays: Bool {
        daysRemaining <= 2 && daysRemaining > 0
    }
    
    private var isExpired: Bool {
        trialState?.isExpired ?? false
    }
    
    // UI Configuration based on trial state
    private var modalTitle: String {
        if isExpired {
            return "Trial Expired"
        } else if isLastTwoDays {
            return "Trial Ending Soon!"
        } else {
            return "Free Trial Active"
        }
    }
    
    private var modalIcon: String {
        if isExpired {
            return "lock.fill"
        } else if daysRemaining <= 2 {
            return "clock.badge.exclamationmark"
        } else if daysRemaining <= 4 {
            return "calendar.badge.clock"
        } else {
            return "calendar.circle"
        }
    }
    
    private var modalIconColor: Color {
        if isExpired {
            return .red
        } else if daysRemaining <= 2 {
            return .orange
        } else if daysRemaining <= 4 {
            return .yellow
        } else {
            return .blue
        }
    }
    
    private var messageText: String {
        if isExpired {
            return "Your 14-day free trial has ended. Subscribe now to regain access to your data and continue using HealthGuide."
        } else if daysRemaining == 0 {
            // Day 14 - FINAL DAY
            return "🚨 FINAL DAY - EXPORT YOUR DATA NOW!\n\n• Documents: Open each → Tap (...) → Share\n• Contacts: Screenshot or write down\n• Memos: Save audio recordings\n\n⚠️ Access will be BLOCKED tonight!"
        } else if daysRemaining == 1 {
            // Day 13 - URGENT
            return "⚠️ URGENT: Trial expires TOMORROW!\n\nEXPORT YOUR DATA NOW:\n• Documents: Tap (...) → Share to Files/Email\n• Contacts: Take screenshots or export\n• Memos: Save audio files externally\n\nAfter tomorrow, you'll need to pay to access this data!"
        } else if daysRemaining == 2 {
            // Day 12 - WARNING
            return "⚠️ Only 2 days left!\n\nIf you don't plan to subscribe, remove all documents, memos and contacts as you will lose them.\n\n• Documents → Open each → Delete\n• Contacts → Delete all\n• Memos → Delete recordings"
        } else if daysRemaining <= 4 {
            return "You have \(daysRemaining) days left in your trial. After trial ends, you'll need a subscription to access your data.\n\nRemember to export important documents before day 14."
        } else {
            return "You're on day \(daysUsed + 1) of your 14-day free trial. Enjoy unlimited access to all features!"
        }
    }
    
    private var dismissable: Bool {
        // Can't dismiss on day 14 or after (hard paywall)
        // Day 14 = 0 days remaining, must subscribe or lose access
        daysRemaining > 0 && !isExpired
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Drag indicator (only if dismissable)
                if dismissable {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                }
                
                // Icon and Title
                VStack(spacing: 16) {
                Image(systemName: modalIcon)
                    .font(.system(size: 50))
                    .foregroundColor(modalIconColor)
                    .symbolEffect(.bounce, value: isPresented)
                
                Text(modalTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Days remaining badge
                if !isExpired {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                        
                        if daysRemaining == 0 {
                            Text("Last day of trial")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            Text("\(daysRemaining) \(daysRemaining == 1 ? "day" : "days") remaining")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isLastTwoDays ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                    )
                    .foregroundColor(isLastTwoDays ? .orange : .blue)
                }
                
                // Message
                Text(messageText)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            .padding(.horizontal)
            
            // Trial Progress Bar (if not expired)
            if !isExpired {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Trial Progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Day \(daysUsed + 1) of 14")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: isLastTwoDays ? [.orange, .red] : [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * (Double(daysUsed + 1) / 14.0), height: 8)
                                .animation(.spring(), value: daysUsed)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal)
                .padding(.top, 24)
            }
            
            // App Features (using exact TabBar icons)
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "heart.text.clipboard")
                        .foregroundColor(.red)
                        .font(.system(size: 20))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MyHealth")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add, Track medications, supplements & diet daily")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "person.3")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Groups")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Create groups up to 3 members, multiple admins")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contacts")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Store all relevant contacts in one place")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "mic.circle")
                        .foregroundColor(.orange)
                        .font(.system(size: 20))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memos")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Store up to 10 audio memos")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.purple)
                        .font(.system(size: 20))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vault")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Organize and store up to 15 MB of documents")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .padding(.horizontal)
            .padding(.top, 20)
            
            // Privacy badge - reassuring for 60+ caregivers
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text("No email or phone required • Fully anonymous")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Subscribe button
            Button(action: {
                Task {
                    await subscribeTapped()
                }
            }) {
                HStack {
                    if isProcessingPayment {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Text(isExpired ? "Subscribe Now - $8.99/month" : "Start Subscription - $8.99/month")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isExpired ? Color.red : (isLastTwoDays ? Color.orange : Color.blue))
                )
                .foregroundColor(.white)
            }
            .disabled(isProcessingPayment)
            .padding(.horizontal)
            .padding(.top, 20)
            
            
            // Dismiss button (only if dismissable - NOT on day 14)
            if dismissable {
                Button(action: {
                    isPresented = false
                }) {
                    Text(daysRemaining == 1 ? "I'll Export Tomorrow" : "Continue Trial")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            } else if daysRemaining == 0 {
                // Day 14 - Cannot dismiss
                Text("⚠️ Cannot dismiss - Subscribe or Export Now")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 12)
            }
            
            // Bottom spacing
            Spacer()
                .frame(height: 20)
            }
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20, corners: [.topLeft, .topRight])
        .shadow(radius: 20)
        .alert("Subscription Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Actions
    
    private func subscribeTapped() async {
        isProcessingPayment = true
        
        do {
            // Purchase subscription
            try await subscriptionManager.purchase()
            
            // Success - dismiss modal
            await MainActor.run {
                isPresented = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
                isProcessingPayment = false
            }
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

@available(iOS 18.0, *)
struct TrialStatusModal_Previews: PreviewProvider {
    static var previews: some View {
        TrialStatusModal(isPresented: .constant(true))
            .environmentObject(SubscriptionManager.shared)
    }
}