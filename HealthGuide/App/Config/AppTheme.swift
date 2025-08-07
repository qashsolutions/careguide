
//  HealthGuide - AppTheme.swift
//  HealthGuide
//  Design system: colors, fonts, spacing
//  Single source of truth for all UI styling

import SwiftUI

@available(iOS 18.0, *)
struct AppTheme {
    
    // MARK: - Colors
    struct Colors {
        // Primary Card Header Colors (from coding_standards.md)
        static let medicationBlue = Color(hex: "#1f3a93")    // Dark blue
        static let supplementGreen = Color(hex: "#34C759")   // iOS system green
        static let dietBlue = Color(hex: "#87ceeb")          // Light blue
        
        // System Colors
        static let primaryBlue = Color(hex: "#007AFF")       // iOS system blue
        static let secondaryPurple = Color(hex: "#5856D6")   // iOS system purple
        static let successGreen = Color(hex: "#34C759")      // iOS system green
        static let warningOrange = Color(hex: "#FF9500")     // iOS system orange
        static let errorRed = Color(hex: "#FF3B30")          // iOS system red
        
        // Background Colors
        static let backgroundPrimary = Color(hex: "#FFFFFF")
        static let backgroundSecondary = Color(hex: "#F8F9FF")
        static let cardBackground = Color.white.opacity(0.9)
        
        // Text Colors
        static let textPrimary = Color(hex: "#1D1D1F")
        static let textSecondary = Color(hex: "#86868B")
        static let textOnDark = Color.white
        
        // Border Colors
        static let borderLight = Color.black.opacity(0.05)
        static let borderMedium = Color.black.opacity(0.1)
        static let borderFocus = Color(hex: "#007AFF")  // iOS system blue
        
        // Glass Effect
        static let glassBackground = Color.white.opacity(0.8)
        static let glassOverlay = Color.white.opacity(0.2)
    }
    
    // MARK: - Typography
    struct Typography {
        // Font Names
        static let primaryFont = ".SF Pro Text"  // San Francisco system font
        static let fallbackFont = "System"
        
        // Font Sizes
        static let largeTitle: CGFloat = 34
        static let title: CGFloat = 28
        static let headline: CGFloat = 24
        static let body: CGFloat = 17
        static let callout: CGFloat = 16
        static let subheadline: CGFloat = 15
        static let footnote: CGFloat = 14
        static let caption: CGFloat = 12
        
        // Card Specific
        static let cardHeader: CGFloat = 14
        static let cardTitle: CGFloat = 22
        static let cardSubtitle: CGFloat = 17
        static let medicationName: CGFloat = 17
        static let medicationDose: CGFloat = 15
        
        // Font Weights
        static let bold = Font.Weight.bold
        static let semibold = Font.Weight.semibold
        static let medium = Font.Weight.medium
        static let regular = Font.Weight.regular
    }
    
    // MARK: - Elder-Friendly Typography
    struct ElderTypography {
        // Reduced by 2px per caregiver feedback - users can adjust using iOS accessibility settings
        static let largeTitle: CGFloat = 40      // was 42 (previously 46, originally 34)
        static let title: CGFloat = 32           // was 34 (previously 38, originally 28)
        static let headline: CGFloat = 26        // was 28 (previously 32, originally 24)
        static let body: CGFloat = 18            // was 20 (previously 24, originally 17)
        static let callout: CGFloat = 16         // was 18 (previously 22, originally 16)
        static let subheadline: CGFloat = 14     // was 16 (previously 20, originally 15)
        static let footnote: CGFloat = 13        // was 15 (previously 19, originally 14)
        static let caption: CGFloat = 11         // was 13 (previously 17, originally 12)
        
        // Card Specific - Critical for medication visibility
        static let cardHeader: CGFloat = 13      // was 15 (previously 19, originally 14)
        static let cardTitle: CGFloat = 24       // was 26 (previously 30, originally 22)
        static let cardSubtitle: CGFloat = 18    // was 20 (previously 24, originally 17)
        static let medicationName: CGFloat = 20  // was 22 (previously 26, originally 17)
        static let medicationDose: CGFloat = 16  // was 18 (previously 22, originally 15)
        
        // Use same font weights as Typography
        static let bold = Typography.bold
        static let semibold = Typography.semibold
        static let medium = Typography.medium
        static let regular = Typography.regular
    }
    
    // MARK: - Spacing
    struct Spacing {
        // Base spacing units
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
        static let xxxLarge: CGFloat = 40
        
        // Component specific
        static let cardPadding: CGFloat = 20
        static let cardHeaderPadding: CGFloat = 12
        static let cardMargin: CGFloat = 16
        static let screenPadding: CGFloat = 20
        static let tabBarPadding: CGFloat = 8
    }
    
    // MARK: - Dimensions
    struct Dimensions {
        // Touch targets
        static let minimumTouchTarget: CGFloat = 44
        static let buttonHeight: CGFloat = 50
        static let elderButtonHeight: CGFloat = 60  // Larger for elder users
        static let inputFieldHeight: CGFloat = 50
        
        // Corner Radii
        static let cardCornerRadius: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 12
        static let inputCornerRadius: CGFloat = 12
        static let badgeCornerRadius: CGFloat = 12
        static let phoneCornerRadius: CGFloat = 40
        static let screenCornerRadius: CGFloat = 32
        
        // Borders
        static let borderWidth: CGFloat = 1
        static let focusBorderWidth: CGFloat = 2
        
        // Icons
        static let tabIconSize: CGFloat = 24
        static let largeIconSize: CGFloat = 60
        static let aiIconSize: CGFloat = 24
        
        // Specific Components
        static let addButtonSize: CGFloat = 44
        static let checkboxSize: CGFloat = 24
        static let skeletonHeight: CGFloat = 20
    }
    
    // MARK: - Effects
    struct Effects {
        static let backdropBlur: CGFloat = 20
        static let cardShadowRadius: CGFloat = 20
        static let cardShadowOpacity: CGFloat = 0.08
        static let buttonShadowRadius: CGFloat = 12
        static let buttonShadowOpacity: CGFloat = 0.3
        static let glassOpacity: CGFloat = 0.9
        static let animationDuration: CGFloat = 0.3
    }
    
    // MARK: - Layout
    struct Layout {
        static let phoneWidth: CGFloat = 375
        static let phoneHeight: CGFloat = 812
        static let statusBarHeight: CGFloat = 44
        static let tabBarHeight: CGFloat = 83
        static let maxContentWidth: CGFloat = 600
    }
    
    // MARK: - Semantic Colors
    struct Semantic {
        // Status colors
        static let success = Colors.successGreen
        static let warning = Colors.warningOrange
        static let error = Colors.errorRed
        static let info = Colors.primaryBlue
        
        // Time-based colors for dose tracking
        static let pastDue = Colors.errorRed
        static let current = Colors.primaryBlue
        static let upcoming = Colors.textSecondary
        static let completed = Colors.successGreen
    }
}

// MARK: - Dynamic Type Support
@available(iOS 18.0, *)
extension Font {
    /// System font with Dynamic Type support for elderly users
    static func monaco(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        // Use San Francisco (system font) instead of Monaco to avoid missing font issues
        // .rounded design provides better readability for elderly users
        return Font.system(size: size, weight: .regular, design: .rounded)
    }
    
    /// System font with Dynamic Type support
    static func appFont(_ style: Font.TextStyle) -> Font {
        return Font.system(style, design: .default)
    }
    
    /// Safe custom font loader with fallback
    static func customFont(_ name: String, size: CGFloat) -> Font {
        // Always use system font to avoid missing font crashes
        return Font.system(size: size, weight: .regular, design: .default)
    }
}

// MARK: - View Modifiers
@available(iOS 18.0, *)
extension View {
    /// Apply liquid glass effect with proper blur values
    func liquidGlassEffect() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(AppTheme.Effects.glassOpacity)
            )
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .stroke(AppTheme.Colors.borderLight, lineWidth: AppTheme.Dimensions.borderWidth)
            )
    }
    
    /// Support Dynamic Type for elderly users with vision issues
    func supportsDynamicType() -> some View {
        self
            .dynamicTypeSize(...DynamicTypeSize.accessibility3) // Support up to XXXL
    }
}

// MARK: - Color Extension
@available(iOS 18.0, *)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
