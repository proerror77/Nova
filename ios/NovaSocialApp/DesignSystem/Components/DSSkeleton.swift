import SwiftUI

/// 骨架屏组件 - 用于内容加载时的占位显示
/// Skeleton Component - Placeholder display during content loading
public struct DSSkeleton: View {

    // MARK: - Shape

    public enum Shape {
        case rectangle
        case circle
        case rounded(cornerRadius: CGFloat)
        case custom(AnyView)

        @ViewBuilder
        func makeView(width: CGFloat?, height: CGFloat?) -> some View {
            switch self {
            case .rectangle:
                Rectangle()
                    .frame(width: width, height: height)

            case .circle:
                Circle()
                    .frame(width: width ?? height, height: height ?? width)

            case .rounded(let cornerRadius):
                RoundedRectangle(cornerRadius: cornerRadius)
                    .frame(width: width, height: height)

            case .custom(let view):
                view
                    .frame(width: width, height: height)
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let shape: Shape
    private let width: CGFloat?
    private let height: CGFloat?
    private let animated: Bool

    // MARK: - Initialization

    public init(
        shape: Shape = .rounded(cornerRadius: DesignTokens.BorderRadius.md),
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        animated: Bool = true
    ) {
        self.shape = shape
        self.width = width
        self.height = height
        self.animated = animated
    }

    // MARK: - Body

    public var body: some View {
        shape.makeView(width: width, height: height)
            .fill(theme.colors.surfaceVariant)
            .modifier(animated ? AnyViewModifier(ShimmerModifier()) : AnyViewModifier(EmptyModifier()))
    }
}

// MARK: - Skeleton Presets

extension DSSkeleton {

    /// 文本骨架屏
    public static func text(
        lines: Int = 1,
        lineHeight: CGFloat = 16,
        spacing: CGFloat = 8
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<lines, id: \.self) { index in
                DSSkeleton(
                    height: lineHeight
                )
                .frame(maxWidth: index == lines - 1 ? .infinity * 0.7 : .infinity)
            }
        }
    }

    /// 圆形头像骨架屏
    public static func avatar(size: CGFloat = 40) -> some View {
        DSSkeleton(
            shape: .circle,
            width: size,
            height: size
        )
    }

    /// 矩形图片骨架屏
    public static func image(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        aspectRatio: CGFloat? = nil
    ) -> some View {
        DSSkeleton(
            shape: .rounded(cornerRadius: DesignTokens.BorderRadius.md),
            width: width,
            height: height
        )
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    /// 按钮骨架屏
    public static func button(
        width: CGFloat = 120,
        height: CGFloat = 44
    ) -> some View {
        DSSkeleton(
            shape: .rounded(cornerRadius: DesignTokens.BorderRadius.Component.button),
            width: width,
            height: height
        )
    }
}

// MARK: - Skeleton Card

/// 卡片骨架屏模板
public struct DSSkeletonCard: View {

    @Environment(\.appTheme) private var theme

    public enum Style {
        case post      // 社交媒体帖子
        case profile   // 用户资料
        case article   // 文章卡片
    }

    private let style: Style

    public init(style: Style = .post) {
        self.style = style
    }

    public var body: some View {
        Group {
            switch style {
            case .post:
                postSkeleton
            case .profile:
                profileSkeleton
            case .article:
                articleSkeleton
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(theme.colors.cardBackground)
        .cornerRadius(DesignTokens.BorderRadius.Component.card)
    }

    private var postSkeleton: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Header (Avatar + Name)
            HStack(spacing: DesignTokens.Spacing.sm) {
                DSSkeleton.avatar(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    DSSkeleton(width: 120, height: 16)
                    DSSkeleton(width: 80, height: 12)
                }
                Spacer()
            }

            // Content
            DSSkeleton.text(lines: 3)

            // Image
            DSSkeleton.image(height: 200)

            // Actions
            HStack(spacing: DesignTokens.Spacing.lg) {
                DSSkeleton(width: 60, height: 24)
                DSSkeleton(width: 60, height: 24)
                DSSkeleton(width: 60, height: 24)
                Spacer()
            }
        }
    }

    private var profileSkeleton: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            DSSkeleton.avatar(size: 80)
            DSSkeleton(width: 150, height: 20)
            DSSkeleton(width: 200, height: 14)

            HStack(spacing: DesignTokens.Spacing.xl) {
                VStack {
                    DSSkeleton(width: 50, height: 24)
                    DSSkeleton(width: 60, height: 12)
                }
                VStack {
                    DSSkeleton(width: 50, height: 24)
                    DSSkeleton(width: 60, height: 12)
                }
                VStack {
                    DSSkeleton(width: 50, height: 24)
                    DSSkeleton(width: 60, height: 12)
                }
            }

            DSSkeleton.button(width: 200, height: 44)
        }
    }

    private var articleSkeleton: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            DSSkeleton.image(height: 150)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                DSSkeleton(height: 24)
                    .frame(maxWidth: .infinity * 0.9)

                DSSkeleton.text(lines: 2)

                HStack {
                    DSSkeleton.avatar(size: 24)
                    DSSkeleton(width: 100, height: 12)
                    Spacer()
                    DSSkeleton(width: 60, height: 12)
                }
            }
        }
    }
}

// MARK: - Skeleton List

/// 骨架屏列表
public struct DSSkeletonList: View {

    private let count: Int
    private let cardStyle: DSSkeletonCard.Style

    public init(count: Int = 3, cardStyle: DSSkeletonCard.Style = .post) {
        self.count = count
        self.cardStyle = cardStyle
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ForEach(0..<count, id: \.self) { _ in
                DSSkeletonCard(style: cardStyle)
            }
        }
    }
}

// MARK: - Helper Types

private struct AnyViewModifier: ViewModifier {
    private let _body: (Content) -> AnyView

    init<M: ViewModifier>(_ modifier: M) {
        _body = { AnyView(modifier.body(content: $0)) }
    }

    func body(content: Content) -> some View {
        _body(content)
    }
}

// MARK: - Previews

#if DEBUG
struct DSSkeleton_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                Group {
                    Text("Basic Shapes")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.md) {
                        DSSkeleton(width: 100, height: 100)
                        DSSkeleton(shape: .circle, width: 100, height: 100)
                        DSSkeleton(
                            shape: .rounded(cornerRadius: 20),
                            width: 100,
                            height: 100
                        )
                    }
                }

                Divider()

                Group {
                    Text("Presets")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        HStack {
                            DSSkeleton.avatar()
                            VStack(alignment: .leading) {
                                DSSkeleton(width: 120, height: 16)
                                DSSkeleton(width: 80, height: 12)
                            }
                        }

                        DSSkeleton.text(lines: 3)

                        DSSkeleton.image(height: 200)

                        DSSkeleton.button()
                    }
                }

                Divider()

                Group {
                    Text("Card Templates")
                        .font(.headline)

                    DSSkeletonCard(style: .post)
                    DSSkeletonCard(style: .profile)
                    DSSkeletonCard(style: .article)
                }

                Divider()

                Group {
                    Text("Skeleton List")
                        .font(.headline)

                    DSSkeletonList(count: 2, cardStyle: .post)
                }
            }
            .padding()
        }
        .withThemeManager()
        .previewDisplayName("Light Mode")

        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                DSSkeleton.avatar(size: 60)
                DSSkeleton.text(lines: 2)
                DSSkeletonCard(style: .post)
            }
            .padding()
        }
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
        .background(Color.black)
        .previewDisplayName("Dark Mode")
    }
}
#endif
