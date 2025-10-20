import SwiftUI

// MARK: - Card Modifier

/// 卡片样式修饰符
struct CardModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let padding: CGFloat
    let cornerRadius: CGFloat
    let shadowStyle: DesignTokens.Shadow.ShadowStyle

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(theme.colors.cardBackground)
            .cornerRadius(cornerRadius)
            .shadow(
                color: shadowStyle.color,
                radius: shadowStyle.radius,
                x: shadowStyle.x,
                y: shadowStyle.y
            )
    }
}

// MARK: - Input Field Modifier

/// 输入框样式修饰符
struct InputFieldModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let isError: Bool

    func body(content: Content) -> some View {
        content
            .padding(DesignTokens.Spacing.Component.inputPadding)
            .background(theme.colors.inputBackground)
            .cornerRadius(DesignTokens.BorderRadius.Component.input)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.Component.input)
                    .stroke(
                        isError ? theme.colors.error : theme.colors.border,
                        lineWidth: DesignTokens.BorderWidth.thin
                    )
            )
    }
}

// MARK: - Badge Modifier

/// 徽章样式修饰符
struct BadgeModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let color: Color?
    let size: BadgeSize

    enum BadgeSize {
        case small, medium, large

        var padding: CGFloat {
            switch self {
            case .small: return DesignTokens.Spacing.xs
            case .medium: return DesignTokens.Spacing.sm
            case .large: return DesignTokens.Spacing.md
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return DesignTokens.Typography.FontSize.xs
            case .large: return DesignTokens.Typography.FontSize.sm
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size.fontSize, weight: .medium))
            .padding(.horizontal, size.padding * 1.5)
            .padding(.vertical, size.padding)
            .background(color ?? theme.colors.primary)
            .foregroundColor(.white)
            .cornerRadius(DesignTokens.BorderRadius.Component.badge)
    }
}

// MARK: - Section Header Modifier

/// 区块标题修饰符
struct SectionHeaderModifier: ViewModifier {
    @Environment(\.appTheme) var theme

    func body(content: Content) -> some View {
        content
            .font(theme.typography.titleMedium)
            .foregroundColor(theme.colors.text)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.Component.sectionSpacing)
            .padding(.bottom, DesignTokens.Spacing.sm)
    }
}

// MARK: - Divider Modifier

/// 分隔线修饰符
struct StyledDividerModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let thickness: CGFloat
    let color: Color?

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Rectangle()
                .fill(color ?? theme.colors.border)
                .frame(height: thickness)
        }
    }
}

// MARK: - Loading Modifier

/// 加载状态修饰符
struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isLoading ? 0.5 : 1)
                .disabled(isLoading)

            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            }
        }
    }
}

// MARK: - Skeleton Loading Modifier

/// 骨架屏加载修饰符
struct SkeletonModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let isLoading: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isLoading ? 0 : 1)
            .overlay(
                Group {
                    if isLoading {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(theme.colors.surfaceVariant)
                            .shimmer()
                    }
                }
            )
    }
}

// MARK: - Responsive Padding Modifier

/// 响应式内边距修饰符
struct ResponsivePaddingModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalSizeClass == .compact ? DesignTokens.Spacing.md : DesignTokens.Spacing.xl)
    }
}

// MARK: - Safe Area Modifier

/// 安全区域修饰符
struct SafeAreaPaddingModifier: ViewModifier {
    let edges: Edge.Set

    func body(content: Content) -> some View {
        content
            .padding(edges, 0)
            .edgesIgnoringSafeArea(edges.inverted())
    }
}

extension Edge.Set {
    func inverted() -> Edge.Set {
        var result: Edge.Set = []
        if !self.contains(.top) { result.insert(.top) }
        if !self.contains(.bottom) { result.insert(.bottom) }
        if !self.contains(.leading) { result.insert(.leading) }
        if !self.contains(.trailing) { result.insert(.trailing) }
        return result
    }
}

// MARK: - Conditional Modifier

/// 条件修饰符
struct ConditionalModifier<TrueContent: ViewModifier, FalseContent: ViewModifier>: ViewModifier {
    let condition: Bool
    let trueModifier: TrueContent
    let falseModifier: FalseContent

    func body(content: Content) -> some View {
        Group {
            if condition {
                content.modifier(trueModifier)
            } else {
                content.modifier(falseModifier)
            }
        }
    }
}

// MARK: - Glassmorphism Modifier

/// 玻璃态修饰符
struct GlassmorphismModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                theme.colors.surface
                    .opacity(opacity)
                    .blur(radius: blur)
            )
            .background(
                .ultraThinMaterial
            )
            .cornerRadius(DesignTokens.BorderRadius.lg)
    }
}

// MARK: - Neumorphism Modifier

/// 新拟态修饰符
struct NeumorphismModifier: ViewModifier {
    @Environment(\.appTheme) var theme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(theme.colors.background)
                        .shadow(
                            color: theme.isDarkMode ? .white.opacity(0.05) : .black.opacity(0.2),
                            radius: 8,
                            x: -5,
                            y: -5
                        )
                        .shadow(
                            color: theme.isDarkMode ? .black.opacity(0.5) : .white.opacity(0.7),
                            radius: 8,
                            x: 5,
                            y: 5
                        )
                }
            )
    }
}

// MARK: - View Extensions

extension View {

    // MARK: Card Styles

    /// 应用卡片样式
    public func cardStyle(
        padding: CGFloat = DesignTokens.Spacing.Component.cardPadding,
        cornerRadius: CGFloat = DesignTokens.BorderRadius.Component.card,
        shadow: DesignTokens.Shadow.ShadowStyle = DesignTokens.Shadow.md
    ) -> some View {
        modifier(CardModifier(padding: padding, cornerRadius: cornerRadius, shadowStyle: shadow))
    }

    /// 应用输入框样式
    public func inputFieldStyle(isError: Bool = false) -> some View {
        modifier(InputFieldModifier(isError: isError))
    }

    // MARK: Badge Styles

    /// 应用徽章样式
    public func badgeStyle(
        color: Color? = nil,
        size: BadgeModifier.BadgeSize = .medium
    ) -> some View {
        modifier(BadgeModifier(color: color, size: size))
    }

    // MARK: Section Styles

    /// 应用区块标题样式
    public func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderModifier())
    }

    /// 应用分隔线
    public func styledDivider(
        thickness: CGFloat = DesignTokens.BorderWidth.thin,
        color: Color? = nil
    ) -> some View {
        modifier(StyledDividerModifier(thickness: thickness, color: color))
    }

    // MARK: Loading Styles

    /// 应用加载状态
    public func loading(_ isLoading: Bool) -> some View {
        modifier(LoadingModifier(isLoading: isLoading))
    }

    /// 应用骨架屏
    public func skeleton(
        isLoading: Bool,
        cornerRadius: CGFloat = DesignTokens.BorderRadius.md
    ) -> some View {
        modifier(SkeletonModifier(isLoading: isLoading, cornerRadius: cornerRadius))
    }

    // MARK: Layout Styles

    /// 应用响应式内边距
    public func responsivePadding() -> some View {
        modifier(ResponsivePaddingModifier())
    }

    /// 应用安全区域内边距
    public func safeAreaPadding(_ edges: Edge.Set = .all) -> some View {
        modifier(SafeAreaPaddingModifier(edges: edges))
    }

    // MARK: Conditional Styles

    /// 条件应用修饰符
    public func `if`<TrueContent: ViewModifier, FalseContent: ViewModifier>(
        _ condition: Bool,
        then trueModifier: TrueContent,
        else falseModifier: FalseContent
    ) -> some View {
        modifier(ConditionalModifier(
            condition: condition,
            trueModifier: trueModifier,
            falseModifier: falseModifier
        ))
    }

    /// 条件应用修饰符（仅 true 分支）
    public func `if`<Content: ViewModifier>(
        _ condition: Bool,
        then modifier: Content
    ) -> some View {
        Group {
            if condition {
                self.modifier(modifier)
            } else {
                self
            }
        }
    }

    // MARK: Advanced Styles

    /// 应用玻璃态效果
    public func glassmorphism(
        blur: CGFloat = 10,
        opacity: Double = 0.7
    ) -> some View {
        modifier(GlassmorphismModifier(blur: blur, opacity: opacity))
    }

    /// 应用新拟态效果
    public func neumorphism(cornerRadius: CGFloat = DesignTokens.BorderRadius.lg) -> some View {
        modifier(NeumorphismModifier(cornerRadius: cornerRadius))
    }

    // MARK: Accessibility Helpers

    /// 添加辅助功能标签
    public func accessibilityLabel(_ label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(Text(label))
            .if(hint != nil, then: AccessibilityHintModifier(hint: hint!))
    }

    // MARK: Debug Helpers

    #if DEBUG
    /// 显示边框（用于调试布局）
    public func debugBorder(_ color: Color = .red, width: CGFloat = 1) -> some View {
        self.border(color, width: width)
    }

    /// 显示背景色（用于调试布局）
    public func debugBackground(_ color: Color = .red.opacity(0.3)) -> some View {
        self.background(color)
    }
    #endif
}

// MARK: - Helper Modifiers

private struct AccessibilityHintModifier: ViewModifier {
    let hint: String

    func body(content: Content) -> some View {
        content.accessibilityHint(Text(hint))
    }
}

// MARK: - Empty Modifier

struct EmptyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
