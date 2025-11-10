import SwiftUI

/// 设计系统组件展示应用
/// Design System Component Showcase App
@main
struct ComponentShowcaseApp: App {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            ComponentShowcaseView()
                .withThemeManager()
        }
    }
}

// MARK: - Main Showcase View

struct ComponentShowcaseView: View {

    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.appTheme) var theme

    @State private var selectedCategory: ShowcaseCategory = .tokens

    var body: some View {
        NavigationView {
            List {
                ForEach(ShowcaseCategory.allCases) { category in
                    NavigationLink(destination: category.destinationView) {
                        HStack {
                            Image(systemName: category.icon)
                                .font(.system(size: 24))
                                .foregroundColor(theme.colors.primary)
                                .frame(width: 40)

                            VStack(alignment: .leading) {
                                Text(category.title)
                                    .font(theme.typography.titleMedium)
                                Text(category.description)
                                    .font(theme.typography.bodySmall)
                                    .foregroundColor(theme.colors.textSecondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Design System")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    themeToggleButton
                }
            }

            // Initial view
            Text("Select a category to preview components")
                .font(theme.typography.bodyLarge)
                .foregroundColor(theme.colors.textSecondary)
        }
    }

    private var themeToggleButton: some View {
        Button(action: {
            themeManager.toggleTheme()
        }) {
            Image(systemName: themeManager.themeMode.icon)
                .font(.system(size: 20))
        }
    }
}

// MARK: - Showcase Category

enum ShowcaseCategory: String, CaseIterable, Identifiable {
    case tokens
    case colors
    case typography
    case buttons
    case inputs
    case cards
    case badges
    case progress
    case loaders
    case dividers
    case skeletons
    case lists
    case alerts
    case toasts
    case animations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: return "Design Tokens"
        case .colors: return "Colors"
        case .typography: return "Typography"
        case .buttons: return "Buttons"
        case .inputs: return "Input Fields"
        case .cards: return "Cards"
        case .badges: return "Badges & Labels"
        case .progress: return "Progress Bars"
        case .loaders: return "Loaders"
        case .dividers: return "Dividers"
        case .skeletons: return "Skeleton Screens"
        case .lists: return "List Items"
        case .alerts: return "Alerts"
        case .toasts: return "Toasts"
        case .animations: return "Animations"
        }
    }

    var description: String {
        switch self {
        case .tokens: return "Spacing, shadows, and tokens"
        case .colors: return "Color palette and themes"
        case .typography: return "Text styles and fonts"
        case .buttons: return "Button styles and variants"
        case .inputs: return "Text fields and inputs"
        case .cards: return "Card layouts and styles"
        case .badges: return "Badges and status labels"
        case .progress: return "Progress indicators"
        case .loaders: return "Loading animations"
        case .dividers: return "Dividers and separators"
        case .skeletons: return "Loading skeletons"
        case .lists: return "List rows and sections"
        case .alerts: return "Alert dialogs"
        case .toasts: return "Toast notifications"
        case .animations: return "Transitions and animations"
        }
    }

    var icon: String {
        switch self {
        case .tokens: return "cube.fill"
        case .colors: return "paintpalette.fill"
        case .typography: return "textformat"
        case .buttons: return "hand.tap.fill"
        case .inputs: return "keyboard.fill"
        case .cards: return "rectangle.fill"
        case .badges: return "tag.fill"
        case .progress: return "chart.bar.fill"
        case .loaders: return "arrow.triangle.2.circlepath"
        case .dividers: return "minus"
        case .skeletons: return "square.dashed"
        case .lists: return "list.bullet"
        case .alerts: return "exclamationmark.triangle.fill"
        case .toasts: return "message.fill"
        case .animations: return "wand.and.stars"
        }
    }

    @ViewBuilder
    var destinationView: some View {
        switch self {
        case .tokens:
            TokensShowcaseView()
        case .colors:
            ColorsShowcaseView()
        case .typography:
            TypographyShowcaseView()
        case .buttons:
            ButtonsShowcaseView()
        case .inputs:
            InputsShowcaseView()
        case .cards:
            CardsShowcaseView()
        case .badges:
            BadgesShowcaseView()
        case .progress:
            ProgressShowcaseView()
        case .loaders:
            LoadersShowcaseView()
        case .dividers:
            DividersShowcaseView()
        case .skeletons:
            SkeletonsShowcaseView()
        case .lists:
            ListsShowcaseView()
        case .alerts:
            AlertsShowcaseView()
        case .toasts:
            ToastsShowcaseView()
        case .animations:
            AnimationsShowcaseView()
        }
    }
}

// MARK: - Showcase Views

struct TokensShowcaseView: View {
    @Environment(\.appTheme) var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                ShowcaseSection(title: "Spacing Scale") {
                    VStack(alignment: .leading, spacing: 8) {
                        SpacingRow(name: "xs", value: DesignTokens.Spacing.xs)
                        SpacingRow(name: "sm", value: DesignTokens.Spacing.sm)
                        SpacingRow(name: "md", value: DesignTokens.Spacing.md)
                        SpacingRow(name: "lg", value: DesignTokens.Spacing.lg)
                        SpacingRow(name: "xl", value: DesignTokens.Spacing.xl)
                        SpacingRow(name: "xl2", value: DesignTokens.Spacing.xl2)
                        SpacingRow(name: "xl3", value: DesignTokens.Spacing.xl3)
                    }
                }

                ShowcaseSection(title: "Border Radius") {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        RadiusBox(name: "sm", radius: DesignTokens.BorderRadius.sm)
                        RadiusBox(name: "md", radius: DesignTokens.BorderRadius.md)
                        RadiusBox(name: "lg", radius: DesignTokens.BorderRadius.lg)
                        RadiusBox(name: "xl", radius: DesignTokens.BorderRadius.xl)
                    }
                }

                ShowcaseSection(title: "Shadows") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        ShadowBox(name: "sm", shadow: DesignTokens.Shadow.sm)
                        ShadowBox(name: "md", shadow: DesignTokens.Shadow.md)
                        ShadowBox(name: "lg", shadow: DesignTokens.Shadow.lg)
                        ShadowBox(name: "xl", shadow: DesignTokens.Shadow.xl)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Design Tokens")
    }
}

struct ButtonsShowcaseView: View {
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                ShowcaseSection(title: "Button Styles") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        DSButton("Primary Button", style: .primary) {}
                        DSButton("Secondary Button", style: .secondary) {}
                        DSButton("Ghost Button", style: .ghost) {}
                        DSButton("Outline Button", style: .outline) {}
                        DSButton("Destructive Button", style: .destructive) {}
                    }
                }

                ShowcaseSection(title: "Button Sizes") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        DSButton("Small Button", size: .small) {}
                        DSButton("Medium Button", size: .medium) {}
                        DSButton("Large Button", size: .large) {}
                    }
                }

                ShowcaseSection(title: "Button with Icons") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        DSButton("With Leading Icon", icon: "heart.fill") {}
                        DSButton("With Trailing Icon", icon: "arrow.right", iconPosition: .trailing) {}
                        DSButton("Loading State", isLoading: true) {}
                    }
                }

                ShowcaseSection(title: "Icon Buttons") {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        DSIconButton(icon: "heart.fill", style: .primary) {}
                        DSIconButton(icon: "message.fill", style: .secondary) {}
                        DSIconButton(icon: "share", style: .ghost) {}
                        DSIconButton(icon: "trash", style: .destructive) {}
                    }
                }

                ShowcaseSection(title: "Floating Action Button") {
                    DSFloatingActionButton(icon: "plus") {}
                }
            }
            .padding()
        }
        .navigationTitle("Buttons")
    }
}

struct LoadersShowcaseView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                ShowcaseSection(title: "Loader Styles") {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        HStack(spacing: DesignTokens.Spacing.xl) {
                            VStack {
                                DSLoader(style: .circular)
                                Text("Circular")
                            }
                            VStack {
                                DSLoader(style: .dots)
                                Text("Dots")
                            }
                            VStack {
                                DSLoader(style: .bars)
                                Text("Bars")
                            }
                        }

                        HStack(spacing: DesignTokens.Spacing.xl) {
                            VStack {
                                DSLoader(style: .pulse)
                                Text("Pulse")
                            }
                            VStack {
                                DSLoader(style: .spinner)
                                Text("Spinner")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Loaders")
    }
}

// MARK: - Helper Views

struct ShowcaseSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

struct SpacingRow: View {
    @Environment(\.appTheme) var theme
    let name: String
    let value: CGFloat

    var body: some View {
        HStack {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .leading)

            Rectangle()
                .fill(theme.colors.primary)
                .frame(width: value, height: 20)

            Text("\(Int(value))pt")
                .font(.caption)
                .foregroundColor(theme.colors.textSecondary)

            Spacer()
        }
    }
}

struct RadiusBox: View {
    @Environment(\.appTheme) var theme
    let name: String
    let radius: CGFloat

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(theme.colors.primary.opacity(0.2))
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(theme.colors.primary, lineWidth: 2)
                )

            Text(name)
                .font(.caption)
            Text("\(Int(radius))pt")
                .font(.caption2)
                .foregroundColor(theme.colors.textSecondary)
        }
    }
}

struct ShadowBox: View {
    @Environment(\.appTheme) var theme
    let name: String
    let shadow: DesignTokens.Shadow.ShadowStyle

    var body: some View {
        HStack {
            Rectangle()
                .fill(theme.colors.cardBackground)
                .frame(height: 60)
                .shadow(
                    color: shadow.color,
                    radius: shadow.radius,
                    x: shadow.x,
                    y: shadow.y
                )

            Text(name)
                .font(.system(.body, design: .monospaced))

            Spacer()
        }
        .padding()
        .background(theme.colors.surface)
    }
}

// Placeholder views for other showcases
struct ColorsShowcaseView: View {
    var body: some View {
        Text("Colors Showcase").navigationTitle("Colors")
    }
}

struct TypographyShowcaseView: View {
    var body: some View {
        Text("Typography Showcase").navigationTitle("Typography")
    }
}

struct InputsShowcaseView: View {
    var body: some View {
        Text("Inputs Showcase").navigationTitle("Inputs")
    }
}

struct CardsShowcaseView: View {
    var body: some View {
        Text("Cards Showcase").navigationTitle("Cards")
    }
}

struct BadgesShowcaseView: View {
    var body: some View {
        Text("Badges Showcase").navigationTitle("Badges")
    }
}

struct ProgressShowcaseView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                ShowcaseSection(title: "Linear Progress") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        DSProgressBar(progress: 0.3)
                        DSProgressBar(progress: 0.6, showPercentage: true)
                        DSProgressBar(progress: 1.0, color: .green)
                    }
                }

                ShowcaseSection(title: "Circular Progress") {
                    HStack(spacing: DesignTokens.Spacing.lg) {
                        DSProgressBar(progress: 0.25, style: .circular)
                        DSProgressBar(progress: 0.5, style: .circular, showPercentage: true)
                        DSProgressBar(progress: 0.75, style: .circular, color: .orange)
                    }
                }

                ShowcaseSection(title: "Segmented Progress") {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        DSSegmentedProgressBar(totalSteps: 5, currentStep: 2)
                        DSSegmentedProgressBar(totalSteps: 4, currentStep: 3, color: .purple)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Progress Bars")
    }
}

struct DividersShowcaseView: View {
    var body: some View {
        Text("Dividers Showcase").navigationTitle("Dividers")
    }
}

struct SkeletonsShowcaseView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                ShowcaseSection(title: "Skeleton Cards") {
                    DSSkeletonCard(style: .post)
                    DSSkeletonCard(style: .profile)
                    DSSkeletonCard(style: .article)
                }
            }
            .padding()
        }
        .navigationTitle("Skeleton Screens")
    }
}

struct ListsShowcaseView: View {
    var body: some View {
        Text("Lists Showcase").navigationTitle("Lists")
    }
}

struct AlertsShowcaseView: View {
    var body: some View {
        Text("Alerts Showcase").navigationTitle("Alerts")
    }
}

struct ToastsShowcaseView: View {
    var body: some View {
        Text("Toasts Showcase").navigationTitle("Toasts")
    }
}

struct AnimationsShowcaseView: View {
    var body: some View {
        Text("Animations Showcase").navigationTitle("Animations")
    }
}

// MARK: - Previews

#if DEBUG
struct ComponentShowcaseView_Previews: PreviewProvider {
    static var previews: some View {
        ComponentShowcaseView()
            .withThemeManager()
    }
}
#endif
