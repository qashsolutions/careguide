//
//  Color+Extensions.swift
//  HealthGuide
//
//  Color utilities and convenience methods
//  Extends AppTheme colors with additional functionality
//

import SwiftUI

@available(iOS 18.0, *)
extension Color {
    // MARK: - Opacity Helpers
    func veryLight() -> Color {
        self.opacity(0.1)
    }
    
    func light() -> Color {
        self.opacity(0.3)
    }
    
    func medium() -> Color {
        self.opacity(0.5)
    }
    
    func dark() -> Color {
        self.opacity(0.7)
    }
    
    // MARK: - Gradient Helpers
    func asGradient(direction: GradientDirection = .vertical) -> LinearGradient {
        switch direction {
        case .vertical:
            return LinearGradient(
                colors: [self, self.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .horizontal:
            return LinearGradient(
                colors: [self, self.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .diagonal:
            return LinearGradient(
                colors: [self, self.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    enum GradientDirection {
        case vertical
        case horizontal
        case diagonal
    }
    
    // MARK: - Contrast Helpers
    func contrastingTextColor() -> Color {
        // Simple luminance calculation for text contrast
        let components = UIColor(self).cgColor.components ?? [0, 0, 0, 0]
        let red = components[0]
        let green = components[1]
        let blue = components[2]
        
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        
        return luminance > 0.5 ? Color.black : Color.white
    }
    
    // MARK: - Health Type Colors
    static func colorForHealthType(_ type: HealthItemType) -> Color {
        type.headerColor
    }
    
    // MARK: - Status Colors
    static func colorForDoseStatus(isTaken: Bool, isPastDue: Bool, isCurrent: Bool) -> Color {
        if isTaken {
            return AppTheme.Semantic.completed
        } else if isPastDue {
            return AppTheme.Semantic.pastDue
        } else if isCurrent {
            return AppTheme.Semantic.current
        } else {
            return AppTheme.Semantic.upcoming
        }
    }
    
    // MARK: - Conflict Priority Colors
    static func colorForConflictPriority(_ priority: ConflictPriority) -> Color {
        switch priority {
        case .high:
            return AppTheme.Colors.errorRed
        case .medium:
            return AppTheme.Colors.warningOrange
        case .low:
            return AppTheme.Colors.successGreen
        }
    }
}

// MARK: - Conflict Priority
@available(iOS 18.0, *)
enum ConflictPriority: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

// MARK: - UI Color Extensions
@available(iOS 18.0, *)
extension UIColor {
    convenience init(hex: String) {
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
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}

// MARK: - Shape Style Extensions
@available(iOS 18.0, *)
extension ShapeStyle where Self == Color {
    static var medicationHeader: Color { AppTheme.Colors.medicationBlue }
    static var supplementHeader: Color { AppTheme.Colors.supplementGreen }
    static var dietHeader: Color { AppTheme.Colors.dietBlue }
}

// MARK: - Preview Helpers
#Preview {
    VStack(spacing: AppTheme.Spacing.medium) {
        // Health Type Colors
        HStack(spacing: AppTheme.Spacing.medium) {
            ForEach(HealthItemType.allCases, id: \.self) { type in
                RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
                    .fill(type.headerColor)
                    .frame(width: 100, height: 60)
                    .overlay(
                        Text(type.displayName)
                            .font(.monaco(AppTheme.Typography.caption))
                            .foregroundColor(.white)
                    )
            }
        }
        
        // Status Colors
        HStack(spacing: AppTheme.Spacing.medium) {
            Circle()
                .fill(AppTheme.Semantic.completed)
                .frame(width: 50, height: 50)
                .overlay(Text("Taken").font(.caption))
            
            Circle()
                .fill(AppTheme.Semantic.pastDue)
                .frame(width: 50, height: 50)
                .overlay(Text("Due").font(.caption))
            
            Circle()
                .fill(AppTheme.Semantic.current)
                .frame(width: 50, height: 50)
                .overlay(Text("Now").font(.caption))
            
            Circle()
                .fill(AppTheme.Semantic.upcoming)
                .frame(width: 50, height: 50)
                .overlay(Text("Later").font(.caption))
        }
        
        // Gradient Examples
        RoundedRectangle(cornerRadius: AppTheme.Dimensions.cardCornerRadius)
            .fill(AppTheme.Colors.primaryBlue.asGradient())
            .frame(height: 100)
            .overlay(
                Text("Gradient Background")
                    .foregroundColor(.white)
            )
        
        // Opacity Examples
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach([0.1, 0.3, 0.5, 0.7, 1.0], id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.Colors.primaryBlue.opacity(opacity))
                    .frame(width: 60, height: 40)
                    .overlay(
                        Text("\(Int(opacity * 100))%")
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.primaryBlue.opacity(opacity).contrastingTextColor())
                    )
            }
        }
    }
    .padding()
    .background(AppTheme.Colors.backgroundSecondary)
}