//
//  LoadingView.swift
//  HealthGuide
//
//  Loading states with elder-friendly messages
//  Skeleton loading and progress indicators
//

import SwiftUI

@available(iOS 18.0, *)
struct LoadingView: View {
    let message: String
    let showSkeleton: Bool
    
    init(message: String = AppStrings.Loading.loadingSchedule, showSkeleton: Bool = false) {
        self.message = message
        self.showSkeleton = showSkeleton
    }
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            if showSkeleton {
                skeletonView
            } else {
                spinnerView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.backgroundPrimary)
    }
    
    // MARK: - Spinner View
    private var spinnerView: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.primaryBlue))
                .scaleEffect(1.5)
            
            Text(message)
                .font(.monaco(AppTheme.Typography.body))
                .foregroundColor(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xxLarge)
    }
    
    // MARK: - Skeleton View
    private var skeletonView: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            // Header skeleton
            SkeletonCard(showHeader: true)
            
            // Content skeletons
            ForEach(0..<3) { _ in
                SkeletonCard()
            }
            
            Spacer()
        }
        .padding(AppTheme.Spacing.screenPadding)
    }
}

// MARK: - Skeleton Card
@available(iOS 18.0, *)
struct SkeletonCard: View {
    let showHeader: Bool
    @State private var isAnimating = false
    
    init(showHeader: Bool = false) {
        self.showHeader = showHeader
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                // Section header skeleton
                HStack {
                    SkeletonBar(width: 120, height: 20)
                    Spacer()
                }
                .padding(.bottom, AppTheme.Spacing.medium)
            }
            
            // Card skeleton
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                // Title
                SkeletonBar(width: 180, height: AppTheme.Dimensions.skeletonHeight)
                
                // Subtitle
                SkeletonBar(width: 120, height: 16)
                
                // Details
                HStack {
                    SkeletonBar(width: 80, height: 14)
                    Spacer()
                    SkeletonBar(width: 60, height: 28)
                }
                .padding(.top, AppTheme.Spacing.xSmall)
            }
            .padding(AppTheme.Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(AppTheme.Colors.backgroundSecondary)
            )
        }
        .onAppear {
            // OPTIMIZED: Reduced animation for energy efficiency
            // Use longer duration and stop after a few cycles
            withAnimation(Animation.easeInOut(duration: 2.0).repeatCount(5, autoreverses: true)) {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

// MARK: - Skeleton Bar
@available(iOS 18.0, *)
struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        AppTheme.Colors.borderLight,
                        AppTheme.Colors.borderMedium,
                        AppTheme.Colors.borderLight
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .opacity(isAnimating ? 0.6 : 1.0)
            // OPTIMIZED: Use finite animation instead of infinite loop
            .animation(Animation.easeInOut(duration: 2.0).repeatCount(5, autoreverses: true), value: isAnimating)
            .onAppear {
                // Delay animation start to reduce initial load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isAnimating = true
                }
            }
            .onDisappear {
                isAnimating = false
            }
    }
}

// MARK: - Empty State View
@available(iOS 18.0, *)
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.large) {
            Spacer()
            
            Image(systemName: systemImage)
                .font(.system(size: AppTheme.Dimensions.largeIconSize))
                .foregroundColor(AppTheme.Colors.textSecondary.opacity(0.5))
            
            VStack(spacing: AppTheme.Spacing.small) {
                Text(title)
                    .font(.monaco(AppTheme.Typography.headline))
                    .fontWeight(AppTheme.Typography.semibold)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Text(message)
                    .font(.monaco(AppTheme.Typography.body))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xxLarge)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.monaco(AppTheme.Typography.body))
                        .fontWeight(AppTheme.Typography.medium)
                        .foregroundColor(AppTheme.Colors.primaryBlue)
                        .padding(.horizontal, AppTheme.Spacing.large)
                        .padding(.vertical, AppTheme.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Dimensions.buttonCornerRadius)
                                .stroke(AppTheme.Colors.primaryBlue, lineWidth: AppTheme.Dimensions.borderWidth)
                        )
                }
                .frame(minHeight: AppTheme.Dimensions.minimumTouchTarget)
                .padding(.top, AppTheme.Spacing.medium)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.backgroundPrimary)
    }
}

// MARK: - Preview
#Preview {
    VStack {
        LoadingView()
        
        Divider()
        
        LoadingView(message: AppStrings.Loading.processingVoice, showSkeleton: true)
        
        Divider()
        
        EmptyStateView(
            title: "No Medications",
            message: "You haven't added any medications yet",
            systemImage: "pills",
            actionTitle: "Add Medication",
            action: {}
        )
    }
}