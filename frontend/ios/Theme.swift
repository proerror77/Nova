//
//  Theme.swift
//  Nova Design System
//
//  Generated from tokens.design.json
//  Copyright © 2025 Nova. All rights reserved.
//

import SwiftUI

// MARK: - Brand Skin

public enum BrandSkin: String, CaseIterable, Identifiable {
    case brandA
    case brandB

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .brandA: return "Brand A"
        case .brandB: return "Brand B"
        }
    }
}

// MARK: - Theme

public struct Theme {
    public let skin: BrandSkin
    public let dark: Bool
    public let colors: Colors
    public let type: TypeScale
    public let space: Space
    public let metric: Metric
    public let radius: Radius
    public let motion: Motion

    public init(skin: BrandSkin, dark: Bool) {
        self.skin = skin
        self.dark = dark
        self.colors = Colors(skin: skin, dark: dark)
        self.type = TypeScale()
        self.space = Space()
        self.metric = Metric()
        self.radius = Radius()
        self.motion = Motion()
    }

    /// Theme identifier for asset bundle lookup
    public var themeId: String {
        "\(skin.rawValue).\(dark ? "dark" : "light")"
    }
}

// MARK: - Colors

public struct Colors {
    private let skin: BrandSkin
    private let dark: Bool

    init(skin: BrandSkin, dark: Bool) {
        self.skin = skin
        self.dark = dark
    }

    /// Get color by semantic name from the appropriate theme bundle
    public func color(_ name: String) -> Color {
        let themeId = "\(skin.rawValue).\(dark ? "dark" : "light")"
        return Color("\(themeId)/\(name)", bundle: .main)
    }

    // MARK: Background Colors

    public var bgSurface: Color {
        color("bgSurface")
    }

    public var bgElevated: Color {
        color("bgElevated")
    }

    // MARK: Foreground Colors

    public var fgPrimary: Color {
        color("fgPrimary")
    }

    public var fgSecondary: Color {
        color("fgSecondary")
    }

    // MARK: Brand Colors

    public var brandPrimary: Color {
        color("brandPrimary")
    }

    public var brandOn: Color {
        color("brandOn")
    }

    // MARK: Border Colors

    public var borderSubtle: Color {
        color("borderSubtle")
    }

    public var borderStrong: Color {
        color("borderStrong")
    }

    // MARK: State Colors

    public var stateSuccess: Color {
        color("stateSuccess")
    }

    public var stateWarning: Color {
        color("stateWarning")
    }

    public var stateDanger: Color {
        color("stateDanger")
    }
}

// MARK: - Type Scale

public struct TypeScale {
    // Label Small (12pt, 600 weight, 16pt line height)
    public let labelSM = Font.system(size: 12, weight: .semibold)

    // Body Medium (15pt, 400 weight, 22pt line height)
    public let bodyMD = Font.system(size: 15, weight: .regular)

    // Title Large (22pt, 700 weight, 28pt line height)
    public let titleLG = Font.system(size: 22, weight: .bold)

    public init() {}
}

// MARK: - Space

public struct Space {
    public let xs: CGFloat = 4
    public let sm: CGFloat = 8
    public let md: CGFloat = 12
    public let lg: CGFloat = 16
    public let xl: CGFloat = 24
    public let xxl: CGFloat = 32

    public init() {}
}

// MARK: - Metric (Component Dimensions)

public struct Metric {
    // Avatar Sizes
    public let avatarXS: CGFloat = 24
    public let avatarSM: CGFloat = 32
    public let avatarMD: CGFloat = 40
    public let avatarLG: CGFloat = 56

    // Icon Sizes
    public let iconMD: CGFloat = 20
    public let iconLG: CGFloat = 24

    // Post Card Dimensions
    public let postCardPaddingX: CGFloat = 12
    public let postCardPaddingY: CGFloat = 8
    public let postCardCorner: CGFloat = 12

    // Story Dimensions
    public let storyDiameter: CGFloat = 68
    public let storyRing: CGFloat = 2

    // Grid Layout
    public let gridProfileColumns: Int = 3
    public let gridGap: CGFloat = 2
    public let gridThumbCorner: CGFloat = 4

    // Hit Area
    public let hitAreaMin: CGFloat = 44

    public init() {}
}

// MARK: - Radius

public struct Radius {
    public let sm: CGFloat = 8
    public let md: CGFloat = 12
    public let lg: CGFloat = 16

    public init() {}
}

// MARK: - Motion

public struct Motion {
    public let durationFast: TimeInterval = 0.12
    public let durationBase: TimeInterval = 0.20
    public let durationSlow: TimeInterval = 0.32

    // Standard easing curve (0.2, 0, 0, 1)
    public let easingStandard = Animation.timingCurve(0.2, 0, 0, 1)

    public init() {}
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(skin: .brandA, dark: false)
}

extension EnvironmentValues {
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Apply a theme to the view hierarchy
    public func theme(_ theme: Theme) -> some View {
        self.environment(\.theme, theme)
            .preferredColorScheme(theme.dark ? .dark : .light)
    }

    /// Apply theme with individual parameters
    public func theme(skin: BrandSkin = .brandA, dark: Bool = false) -> some View {
        let theme = Theme(skin: skin, dark: dark)
        return self.environment(\.theme, theme)
            .preferredColorScheme(dark ? .dark : .light)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension Theme {
    /// All available theme combinations for previews
    public static var allCombinations: [Theme] {
        BrandSkin.allCases.flatMap { skin in
            [
                Theme(skin: skin, dark: false),
                Theme(skin: skin, dark: true)
            ]
        }
    }

    /// Preview helpers
    public static let brandALight = Theme(skin: .brandA, dark: false)
    public static let brandADark = Theme(skin: .brandA, dark: true)
    public static let brandBLight = Theme(skin: .brandB, dark: false)
    public static let brandBDark = Theme(skin: .brandB, dark: true)
}
#endif
