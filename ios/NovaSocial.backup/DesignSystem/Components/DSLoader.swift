import SwiftUI

/// 加载指示器组件 - 显示加载状态
/// Loader Component - Display loading state
public struct DSLoader: View {

    // MARK: - Style

    public enum Style {
        case circular       // 圆形旋转
        case dots           // 点状跳动
        case bars           // 条状波动
        case pulse          // 脉冲缩放
        case spinner        // 自定义旋转器

        var defaultSize: CGFloat {
            switch self {
            case .circular, .spinner: return 40
            case .dots, .bars: return 30
            case .pulse: return 50
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let style: Style
    private let color: Color?
    private let size: CGFloat?
    private let lineWidth: CGFloat

    // MARK: - Initialization

    public init(
        style: Style = .circular,
        color: Color? = nil,
        size: CGFloat? = nil,
        lineWidth: CGFloat = 3
    ) {
        self.style = style
        self.color = color
        self.size = size
        self.lineWidth = lineWidth
    }

    // MARK: - Body

    public var body: some View {
        let loaderColor = color ?? theme.colors.primary

        Group {
            switch style {
            case .circular:
                CircularLoader(color: loaderColor, size: size ?? style.defaultSize, lineWidth: lineWidth)
            case .dots:
                DotsLoader(color: loaderColor, size: size ?? style.defaultSize)
            case .bars:
                BarsLoader(color: loaderColor, size: size ?? style.defaultSize)
            case .pulse:
                PulseLoader(color: loaderColor, size: size ?? style.defaultSize)
            case .spinner:
                SpinnerLoader(color: loaderColor, size: size ?? style.defaultSize, lineWidth: lineWidth)
            }
        }
    }
}

// MARK: - Circular Loader

private struct CircularLoader: View {
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Dots Loader

private struct DotsLoader: View {
    let color: Color
    let size: CGFloat

    @State private var animatingStates = [false, false, false]

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .scaleEffect(animatingStates[index] ? 1.0 : 0.5)
                    .opacity(animatingStates[index] ? 1.0 : 0.5)
            }
        }
        .onAppear {
            for index in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.2) {
                    withAnimation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                    ) {
                        animatingStates[index] = true
                    }
                }
            }
        }
    }
}

// MARK: - Bars Loader

private struct BarsLoader: View {
    let color: Color
    let size: CGFloat

    @State private var animatingStates = [false, false, false, false, false]

    var body: some View {
        HStack(spacing: size * 0.1) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(color)
                    .frame(width: size * 0.15, height: size)
                    .scaleEffect(y: animatingStates[index] ? 1.0 : 0.3)
            }
        }
        .frame(height: size)
        .onAppear {
            for index in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                    withAnimation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                    ) {
                        animatingStates[index] = true
                    }
                }
            }
        }
    }
}

// MARK: - Pulse Loader

private struct PulseLoader: View {
    let color: Color
    let size: CGFloat

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size, height: size)
                .scaleEffect(isAnimating ? 1.2 : 0.8)

            Circle()
                .fill(color)
                .frame(width: size * 0.6, height: size * 0.6)
                .scaleEffect(isAnimating ? 0.8 : 1.2)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Spinner Loader

private struct SpinnerLoader: View {
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<8) { index in
                RoundedRectangle(cornerRadius: lineWidth / 2)
                    .fill(color)
                    .frame(width: lineWidth, height: size / 3)
                    .offset(y: -size / 3)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .opacity(opacityForIndex(index))
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
        .onAppear {
            withAnimation(
                Animation.linear(duration: 0.8)
                    .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }

    private func opacityForIndex(_ index: Int) -> Double {
        let step = 1.0 / 8.0
        return max(0.2, 1.0 - Double(index) * step)
    }
}

// MARK: - Loading Overlay

/// 全屏加载遮罩
public struct DSLoadingOverlay: View {

    @Environment(\.appTheme) private var theme

    private let isShowing: Bool
    private let text: String?
    private let style: DSLoader.Style

    public init(
        isShowing: Bool,
        text: String? = nil,
        style: DSLoader.Style = .circular
    ) {
        self.isShowing = isShowing
        self.text = text
        self.style = style
    }

    public var body: some View {
        ZStack {
            if isShowing {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: DesignTokens.Spacing.md) {
                    DSLoader(style: style)

                    if let text = text {
                        Text(text)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(.white)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.BorderRadius.lg)
                        .fill(theme.colors.surface)
                )
                .shadow(
                    color: Color.black.opacity(0.2),
                    radius: 10,
                    x: 0,
                    y: 5
                )
            }
        }
        .animation(Animations.standard, value: isShowing)
    }
}

// MARK: - View Extension

extension View {
    /// 添加加载遮罩
    public func loadingOverlay(
        isShowing: Bool,
        text: String? = nil,
        style: DSLoader.Style = .circular
    ) -> some View {
        self.overlay(
            DSLoadingOverlay(isShowing: isShowing, text: text, style: style)
        )
    }
}

// MARK: - Previews

#if DEBUG
struct DSLoader_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                Group {
                    Text("Circular Loader")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.xl) {
                        DSLoader(style: .circular)
                        DSLoader(style: .circular, color: .green)
                        DSLoader(style: .circular, color: .orange, size: 60)
                    }
                }

                Divider()

                Group {
                    Text("Dots Loader")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.xl) {
                        DSLoader(style: .dots)
                        DSLoader(style: .dots, color: .purple)
                        DSLoader(style: .dots, color: .red, size: 40)
                    }
                }

                Divider()

                Group {
                    Text("Bars Loader")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.xl) {
                        DSLoader(style: .bars)
                        DSLoader(style: .bars, color: .blue)
                        DSLoader(style: .bars, color: .pink, size: 40)
                    }
                }

                Divider()

                Group {
                    Text("Pulse Loader")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.xl) {
                        DSLoader(style: .pulse)
                        DSLoader(style: .pulse, color: .teal)
                        DSLoader(style: .pulse, color: .indigo, size: 70)
                    }
                }

                Divider()

                Group {
                    Text("Spinner Loader")
                        .font(.headline)

                    HStack(spacing: DesignTokens.Spacing.xl) {
                        DSLoader(style: .spinner)
                        DSLoader(style: .spinner, color: .cyan)
                        DSLoader(style: .spinner, color: .yellow, size: 60)
                    }
                }

                Divider()

                Group {
                    Text("Loading Overlay Example")
                        .font(.headline)

                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .overlay(
                                Text("Content Area")
                                    .font(.title)
                            )
                    }
                    .loadingOverlay(isShowing: true, text: "Loading...")
                }
            }
            .padding()
        }
        .withThemeManager()
        .previewDisplayName("Light Mode")

        VStack(spacing: DesignTokens.Spacing.xl) {
            DSLoader(style: .circular)
            DSLoader(style: .dots)
            DSLoader(style: .bars)
            DSLoader(style: .pulse)
        }
        .padding()
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
        .background(Color.black)
        .previewDisplayName("Dark Mode")
    }
}
#endif
