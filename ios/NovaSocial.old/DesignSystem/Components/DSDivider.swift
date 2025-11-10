import SwiftUI

/// 分隔符组件 - 用于分隔内容区块
/// Divider Component - Used to separate content blocks
public struct DSDivider: View {

    // MARK: - Direction

    public enum Direction {
        case horizontal
        case vertical
    }

    // MARK: - Style

    public enum Style {
        case solid
        case dashed
        case dotted

        var strokeStyle: StrokeStyle {
            switch self {
            case .solid:
                return StrokeStyle()
            case .dashed:
                return StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 5])
            case .dotted:
                return StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3])
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let direction: Direction
    private let style: Style
    private let color: Color?
    private let thickness: CGFloat
    private let padding: CGFloat

    // MARK: - Initialization

    public init(
        direction: Direction = .horizontal,
        style: Style = .solid,
        color: Color? = nil,
        thickness: CGFloat = DesignTokens.BorderWidth.thin,
        padding: CGFloat = 0
    ) {
        self.direction = direction
        self.style = style
        self.color = color
        self.thickness = thickness
        self.padding = padding
    }

    // MARK: - Body

    public var body: some View {
        Group {
            switch direction {
            case .horizontal:
                horizontalDivider
            case .vertical:
                verticalDivider
            }
        }
        .foregroundColor(color ?? theme.colors.border)
    }

    private var horizontalDivider: some View {
        VStack(spacing: 0) {
            if padding > 0 {
                Spacer().frame(height: padding)
            }

            if style == .solid {
                Rectangle()
                    .fill(color ?? theme.colors.border)
                    .frame(height: thickness)
            } else {
                Rectangle()
                    .stroke(color ?? theme.colors.border, style: style.strokeStyle)
                    .frame(height: thickness)
            }

            if padding > 0 {
                Spacer().frame(height: padding)
            }
        }
    }

    private var verticalDivider: some View {
        HStack(spacing: 0) {
            if padding > 0 {
                Spacer().frame(width: padding)
            }

            if style == .solid {
                Rectangle()
                    .fill(color ?? theme.colors.border)
                    .frame(width: thickness)
            } else {
                Rectangle()
                    .stroke(color ?? theme.colors.border, style: style.strokeStyle)
                    .frame(width: thickness)
            }

            if padding > 0 {
                Spacer().frame(width: padding)
            }
        }
    }
}

// MARK: - Text Divider

/// 带文本的分隔符
public struct DSTextDivider: View {

    @Environment(\.appTheme) private var theme

    private let text: String
    private let color: Color?

    public init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            DSDivider()
            Text(text)
                .font(theme.typography.labelMedium)
                .foregroundColor(color ?? theme.colors.textSecondary)
            DSDivider()
        }
    }
}

// MARK: - Icon Divider

/// 带图标的分隔符
public struct DSIconDivider: View {

    @Environment(\.appTheme) private var theme

    private let icon: String
    private let color: Color?

    public init(icon: String, color: Color? = nil) {
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            DSDivider()
            Image(systemName: icon)
                .font(.system(size: DesignTokens.IconSize.sm))
                .foregroundColor(color ?? theme.colors.textSecondary)
            DSDivider()
        }
    }
}

// MARK: - Inset Divider

/// 内嵌分隔符（列表常用）
public struct DSInsetDivider: View {

    @Environment(\.appTheme) private var theme

    private let leadingInset: CGFloat
    private let trailingInset: CGFloat

    public init(leadingInset: CGFloat = DesignTokens.Spacing.md, trailingInset: CGFloat = 0) {
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }

    public var body: some View {
        HStack(spacing: 0) {
            if leadingInset > 0 {
                Color.clear.frame(width: leadingInset)
            }

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: DesignTokens.BorderWidth.thin)

            if trailingInset > 0 {
                Color.clear.frame(width: trailingInset)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct DSDivider_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                Group {
                    Text("Horizontal Dividers")
                        .font(.headline)

                    VStack(spacing: DesignTokens.Spacing.md) {
                        Text("Solid")
                        DSDivider()

                        Text("Dashed")
                        DSDivider(style: .dashed)

                        Text("Dotted")
                        DSDivider(style: .dotted)

                        Text("Thick")
                        DSDivider(thickness: 3)

                        Text("Colored")
                        DSDivider(color: .blue, thickness: 2)

                        Text("With Padding")
                        DSDivider(padding: DesignTokens.Spacing.md)
                    }
                }

                Group {
                    Text("Vertical Dividers")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.md) {
                        Text("Left")
                        DSDivider(direction: .vertical)
                            .frame(height: 50)
                        Text("Middle")
                        DSDivider(direction: .vertical, style: .dashed)
                            .frame(height: 50)
                        Text("Right")
                    }
                }

                Group {
                    Text("Text Dividers")
                        .font(.headline)

                    DSTextDivider("OR")
                    DSTextDivider("SECTION 1", color: .purple)
                }

                Group {
                    Text("Icon Dividers")
                        .font(.headline)

                    DSIconDivider(icon: "star.fill")
                    DSIconDivider(icon: "heart.fill", color: .red)
                }

                Group {
                    Text("Inset Dividers (for Lists)")
                        .font(.headline)

                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                            VStack(alignment: .leading) {
                                Text("John Doe")
                                    .font(.headline)
                                Text("Software Developer")
                                    .font(.caption)
                            }
                            Spacer()
                        }
                        .padding()

                        DSInsetDivider(leadingInset: 64)

                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                            VStack(alignment: .leading) {
                                Text("Jane Smith")
                                    .font(.headline)
                                Text("Product Manager")
                                    .font(.caption)
                            }
                            Spacer()
                        }
                        .padding()
                    }
                }
            }
            .padding()
        }
        .withThemeManager()
        .previewDisplayName("Light Mode")

        VStack(spacing: DesignTokens.Spacing.xl) {
            DSDivider()
            DSDivider(style: .dashed)
            DSTextDivider("OR")
            DSIconDivider(icon: "star.fill")
        }
        .padding()
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
        .background(Color.black)
        .previewDisplayName("Dark Mode")
    }
}
#endif
