import SwiftUI

// MARK: - Environment Key for Theme
private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemeMode = .system
}

extension EnvironmentValues {
    var themeMode: ThemeMode {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum ThemeMode {
    case light
    case dark
    case system

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Theme Extensions for Adaptive Colors
extension Theme.Colors {
    /// Adaptive colors that change based on color scheme
    static func adaptiveBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "121212") : Color(hex: "F5F5F5")
    }

    static func adaptiveSurface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "1E1E1E") : Color.white
    }

    static func adaptiveTextPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white : Color(hex: "212121")
    }

    static func adaptiveTextSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "AAAAAA") : Color(hex: "757575")
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
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

// MARK: - Responsive Spacing
extension Theme.Spacing {
    /// Dynamic spacing based on device size
    static func responsive(_ base: CGFloat) -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth <= 375 {
            return base * 0.9 // iPhone SE, 8
        } else if screenWidth >= 428 {
            return base * 1.1 // iPhone 14 Pro Max
        }
        return base
    }
}

// MARK: - Responsive Typography
extension Theme.Typography {
    /// Dynamic font sizes for accessibility
    static func scaledFont(_ font: Font, category: UIContentSizeCategory = .large) -> Font {
        // SwiftUI fonts automatically scale with Dynamic Type
        return font
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Light Mode")
            .foregroundColor(Theme.Colors.adaptiveTextPrimary(for: .light))
            .padding()
            .background(Theme.Colors.adaptiveBackground(for: .light))

        Text("Dark Mode")
            .foregroundColor(Theme.Colors.adaptiveTextPrimary(for: .dark))
            .padding()
            .background(Theme.Colors.adaptiveBackground(for: .dark))
    }
}
