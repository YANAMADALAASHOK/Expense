import SwiftUI

// MARK: - Design System
struct DesignSystem {
    // MARK: - Colors
    struct Colors {
        // Primary Colors
        static let primary = Color("PrimaryColor")
        static let primaryLight = Color("PrimaryLightColor")
        static let primaryDark = Color("PrimaryDarkColor")
        
        // Secondary Colors
        static let secondary = Color("SecondaryColor")
        static let accent = Color("AccentColor")
        
        // Semantic Colors
        static let success = Color("SuccessColor")
        static let warning = Color("WarningColor")
        static let error = Color("ErrorColor")
        static let info = Color("InfoColor")
        
        // Neutral Colors
        static let background = Color("BackgroundColor")
        static let surface = Color("SurfaceColor")
        static let surfaceVariant = Color("SurfaceVariantColor")
        static let outline = Color("OutlineColor")
        
        // Text Colors
        static let onPrimary = Color("OnPrimaryColor")
        static let onSecondary = Color("OnSecondaryColor")
        static let onSurface = Color("OnSurfaceColor")
        static let onSurfaceVariant = Color("OnSurfaceVariantColor")
        
        // Chart Colors
        static let chartColors: [Color] = [
            Color("ChartColor1"),
            Color("ChartColor2"),
            Color("ChartColor3"),
            Color("ChartColor4"),
            Color("ChartColor5"),
            Color("ChartColor6")
        ]
    }
    
    // MARK: - Typography
    struct Typography {
        static let displayLarge = Font.system(size: 57, weight: .regular, design: .default)
        static let displayMedium = Font.system(size: 45, weight: .regular, design: .default)
        static let displaySmall = Font.system(size: 36, weight: .regular, design: .default)
        
        static let headlineLarge = Font.system(size: 32, weight: .semibold, design: .default)
        static let headlineMedium = Font.system(size: 28, weight: .semibold, design: .default)
        static let headlineSmall = Font.system(size: 24, weight: .semibold, design: .default)
        
        static let titleLarge = Font.system(size: 22, weight: .semibold, design: .default)
        static let titleMedium = Font.system(size: 16, weight: .semibold, design: .default)
        static let titleSmall = Font.system(size: 14, weight: .semibold, design: .default)
        
        static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)
        static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)
        
        static let labelLarge = Font.system(size: 14, weight: .medium, design: .default)
        static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
        static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let full: CGFloat = 999
    }
    
    // MARK: - Shadows
    struct Shadows {
        static let small = Shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        static let medium = Shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        static let large = Shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Shadow Model
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions
extension View {
    func applyShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    func cardStyle() -> some View {
        self
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .applyShadow(DesignSystem.Shadows.small)
    }
    
    func primaryButtonStyle() -> some View {
        self
            .background(DesignSystem.Colors.primary)
            .foregroundColor(DesignSystem.Colors.onPrimary)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .applyShadow(DesignSystem.Shadows.small)
    }
    
    func secondaryButtonStyle() -> some View {
        self
            .background(DesignSystem.Colors.surface)
            .foregroundColor(DesignSystem.Colors.primary)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.primary, lineWidth: 1)
            )
    }
} 