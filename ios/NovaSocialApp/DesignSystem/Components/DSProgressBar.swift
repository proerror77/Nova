import SwiftUI

/// 进度条组件 - 显示任务完成进度
/// Progress Bar Component - Display task completion progress
public struct DSProgressBar: View {

    // MARK: - Style

    public enum Style {
        case linear
        case circular

        var defaultHeight: CGFloat {
            switch self {
            case .linear: return 8
            case .circular: return 40
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let progress: Double // 0.0 - 1.0
    private let style: Style
    private let color: Color?
    private let backgroundColor: Color?
    private let showPercentage: Bool
    private let animated: Bool

    // MARK: - Initialization

    public init(
        progress: Double,
        style: Style = .linear,
        color: Color? = nil,
        backgroundColor: Color? = nil,
        showPercentage: Bool = false,
        animated: Bool = true
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.style = style
        self.color = color
        self.backgroundColor = backgroundColor
        self.showPercentage = showPercentage
        self.animated = animated
    }

    // MARK: - Body

    public var body: some View {
        switch style {
        case .linear:
            linearProgressView
        case .circular:
            circularProgressView
        }
    }

    // MARK: - Linear Progress View

    private var linearProgressView: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: style.defaultHeight / 2)
                        .fill(backgroundColor ?? theme.colors.surfaceVariant)
                        .frame(height: style.defaultHeight)

                    // Progress
                    RoundedRectangle(cornerRadius: style.defaultHeight / 2)
                        .fill(color ?? theme.colors.primary)
                        .frame(
                            width: geometry.size.width * CGFloat(progress),
                            height: style.defaultHeight
                        )
                        .animation(animated ? Animations.spring : nil, value: progress)
                }
            }
            .frame(height: style.defaultHeight)

            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.textSecondary)
            }
        }
    }

    // MARK: - Circular Progress View

    private var circularProgressView: some View {
        ZStack {
            // Background Circle
            Circle()
                .stroke(
                    backgroundColor ?? theme.colors.surfaceVariant,
                    lineWidth: 4
                )

            // Progress Circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    color ?? theme.colors.primary,
                    style: StrokeStyle(
                        lineWidth: 4,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(animated ? Animations.spring : nil, value: progress)

            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(theme.typography.titleMedium)
                    .foregroundColor(theme.colors.text)
            }
        }
        .frame(width: style.defaultHeight, height: style.defaultHeight)
    }
}

// MARK: - Indeterminate Progress

/// 不确定进度的加载指示器
public struct DSIndeterminateProgress: View {

    @Environment(\.appTheme) private var theme
    @State private var isAnimating = false

    private let style: DSProgressBar.Style
    private let color: Color?

    public init(
        style: DSProgressBar.Style = .linear,
        color: Color? = nil
    ) {
        self.style = style
        self.color = color
    }

    public var body: some View {
        switch style {
        case .linear:
            linearIndeterminateView
        case .circular:
            circularIndeterminateView
        }
    }

    private var linearIndeterminateView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.colors.surfaceVariant)
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 4)
                    .fill(color ?? theme.colors.primary)
                    .frame(width: geometry.size.width * 0.3, height: 8)
                    .offset(x: isAnimating ? geometry.size.width : -geometry.size.width * 0.3)
                    .onAppear {
                        withAnimation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                        ) {
                            isAnimating = true
                        }
                    }
            }
        }
        .frame(height: 8)
    }

    private var circularIndeterminateView: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: color ?? theme.colors.primary))
            .scaleEffect(1.5)
    }
}

// MARK: - Segmented Progress Bar

/// 分段进度条（多步骤）
public struct DSSegmentedProgressBar: View {

    @Environment(\.appTheme) private var theme

    private let totalSteps: Int
    private let currentStep: Int
    private let color: Color?

    public init(
        totalSteps: Int,
        currentStep: Int,
        color: Color? = nil
    ) {
        self.totalSteps = totalSteps
        self.currentStep = min(max(currentStep, 0), totalSteps)
        self.color = color
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < currentStep ? (color ?? theme.colors.primary) : theme.colors.surfaceVariant)
                    .frame(height: 4)
            }
        }
        .animation(Animations.spring, value: currentStep)
    }
}

// MARK: - Previews

#if DEBUG
struct DSProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Group {
                Text("Linear Progress Bars")
                    .font(.headline)

                DSProgressBar(progress: 0.3)
                DSProgressBar(progress: 0.5, color: .green)
                DSProgressBar(progress: 0.75, showPercentage: true)
                DSProgressBar(progress: 1.0, color: .red)
            }

            Divider()

            Group {
                Text("Circular Progress Bars")
                    .font(.headline)

                HStack(spacing: DesignTokens.Spacing.lg) {
                    DSProgressBar(progress: 0.25, style: .circular)
                    DSProgressBar(progress: 0.5, style: .circular, color: .orange)
                    DSProgressBar(progress: 0.75, style: .circular, showPercentage: true)
                }
            }

            Divider()

            Group {
                Text("Indeterminate Progress")
                    .font(.headline)

                DSIndeterminateProgress()
                DSIndeterminateProgress(style: .circular)
            }

            Divider()

            Group {
                Text("Segmented Progress")
                    .font(.headline)

                DSSegmentedProgressBar(totalSteps: 5, currentStep: 2)
                DSSegmentedProgressBar(totalSteps: 4, currentStep: 3, color: .purple)
            }
        }
        .padding()
        .withThemeManager()
        .previewDisplayName("Light Mode")

        VStack(spacing: DesignTokens.Spacing.xl) {
            DSProgressBar(progress: 0.6, showPercentage: true)
            DSProgressBar(progress: 0.8, style: .circular, showPercentage: true)
            DSIndeterminateProgress()
        }
        .padding()
        .environmentObject(ThemeManager.previewDark)
        .appTheme(ThemeManager.previewDark.currentTheme)
        .background(Color.black)
        .previewDisplayName("Dark Mode")
    }
}
#endif
