import SwiftUI

/// 动画系统 - 预定义的动画和过渡效果
/// Animation System - Predefined animations and transition effects
public enum Animations {

    // MARK: - Standard Animations

    /// 快速动画（按钮点击等）
    public static let fast = Animation.easeOut(duration: DesignTokens.Duration.fast)

    /// 标准动画（大多数 UI 交互）
    public static let standard = Animation.easeInOut(duration: DesignTokens.Duration.normal)

    /// 慢速动画（页面过渡等）
    public static let slow = Animation.easeInOut(duration: DesignTokens.Duration.slow)

    /// 弹簧动画（有弹性效果）
    public static let spring = DesignTokens.Easing.spring

    /// 弹性弹簧动画（更有弹性）
    public static let springBouncy = DesignTokens.Easing.springBouncy

    /// 平滑弹簧动画（无过冲）
    public static let springSmooth = DesignTokens.Easing.springSmooth

    // MARK: - Transitions

    /// 淡入淡出过渡
    public static let fadeTransition = AnyTransition.opacity
        .animation(standard)

    /// 缩放过渡
    public static let scaleTransition = AnyTransition.scale
        .animation(spring)

    /// 滑入滑出过渡
    public static let slideTransition = AnyTransition.slide
        .animation(standard)

    /// 移动过渡（从底部）
    public static let moveFromBottomTransition = AnyTransition.move(edge: .bottom)
        .animation(standard)

    /// 移动过渡（从顶部）
    public static let moveFromTopTransition = AnyTransition.move(edge: .top)
        .animation(standard)

    /// 移动过渡（从左侧）
    public static let moveFromLeadingTransition = AnyTransition.move(edge: .leading)
        .animation(standard)

    /// 移动过渡（从右侧）
    public static let moveFromTrailingTransition = AnyTransition.move(edge: .trailing)
        .animation(standard)

    /// 组合过渡（淡入 + 缩放）
    public static let fadeScaleTransition = AnyTransition.asymmetric(
        insertion: .scale.combined(with: .opacity),
        removal: .scale.combined(with: .opacity)
    ).animation(spring)

    /// 组合过渡（淡入 + 从底部移动）
    public static let fadeSlideTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .bottom).combined(with: .opacity)
    ).animation(standard)

    // MARK: - Custom Animations

    /// 抖动动画（错误提示）
    public static func shake(offset: CGFloat = 10, duration: Double = 0.6) -> Animation {
        Animation.interpolatingSpring(stiffness: 170, damping: 10)
    }

    /// 脉冲动画（加载等）
    public static func pulse(scale: CGFloat = 1.1, duration: Double = 1.0) -> Animation {
        Animation.easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    /// 旋转动画（刷新等）
    public static func rotate(duration: Double = 1.0) -> Animation {
        Animation.linear(duration: duration).repeatForever(autoreverses: false)
    }

    /// 弹跳动画（通知等）
    public static func bounce(duration: Double = 0.6) -> Animation {
        Animation.interpolatingSpring(stiffness: 300, damping: 10)
    }
}

// MARK: - View Modifiers

/// 淡入动画修饰符
struct FadeInModifier: ViewModifier {
    let delay: Double
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(Animations.standard.delay(delay)) {
                    opacity = 1
                }
            }
    }
}

/// 从底部滑入动画修饰符
struct SlideInFromBottomModifier: ViewModifier {
    let delay: Double
    @State private var offset: CGFloat = 100
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
            .onAppear {
                withAnimation(Animations.spring.delay(delay)) {
                    offset = 0
                    opacity = 1
                }
            }
    }
}

/// 缩放出现动画修饰符
struct ScaleInModifier: ViewModifier {
    let delay: Double
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(Animations.spring.delay(delay)) {
                    scale = 1
                    opacity = 1
                }
            }
    }
}

/// 抖动动画修饰符
struct ShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { shouldShake in
                guard shouldShake else { return }
                performShake()
            }
    }

    private func performShake() {
        let animation = Animation.interpolatingSpring(stiffness: 170, damping: 10)
        let sequence: [CGFloat] = [10, -10, 8, -8, 5, -5, 0]

        for (index, value) in sequence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                withAnimation(animation) {
                    offset = value
                }
            }
        }
    }
}

/// 脉冲动画修饰符
struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .onAppear {
                withAnimation(Animations.pulse()) {
                    isPulsing = true
                }
            }
    }
}

/// 旋转动画修饰符
struct RotateModifier: ViewModifier {
    @State private var isRotating = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(Angle(degrees: isRotating ? 360 : 0))
            .onAppear {
                withAnimation(Animations.rotate()) {
                    isRotating = true
                }
            }
    }
}

/// 骨架屏闪烁动画修饰符
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                    .onAppear {
                        withAnimation(
                            Animation.linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                        ) {
                            phase = 1
                        }
                    }
                }
            )
            .clipped()
    }
}

/// 按钮点击动画修饰符
struct ButtonPressModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .brightness(isPressed ? -0.05 : 0)
            .animation(Animations.fast, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

// MARK: - View Extensions

extension View {

    /// 淡入动画
    public func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }

    /// 从底部滑入动画
    public func slideInFromBottom(delay: Double = 0) -> some View {
        modifier(SlideInFromBottomModifier(delay: delay))
    }

    /// 缩放出现动画
    public func scaleIn(delay: Double = 0) -> some View {
        modifier(ScaleInModifier(delay: delay))
    }

    /// 抖动动画
    public func shake(trigger: Bool) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }

    /// 脉冲动画
    public func pulse() -> some View {
        modifier(PulseModifier())
    }

    /// 旋转动画
    public func rotate() -> some View {
        modifier(RotateModifier())
    }

    /// 骨架屏闪烁动画
    public func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    /// 按钮点击动画
    public func buttonPress() -> some View {
        modifier(ButtonPressModifier())
    }
}

// MARK: - List Row Animations

extension View {

    /// 列表行插入动画
    public func listRowInsert(delay: Double = 0) -> some View {
        self
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(Animations.spring.delay(delay), value: UUID())
    }

    /// 列表行删除动画
    public func listRowDelete() -> some View {
        self
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(Animations.standard, value: UUID())
    }
}

// MARK: - Modal Animations

extension View {

    /// 模态框出现动画
    public func modalAppear() -> some View {
        self
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .animation(Animations.spring, value: UUID())
    }

    /// Sheet 出现动画
    public func sheetAppear() -> some View {
        self
            .transition(.move(edge: .bottom))
            .animation(Animations.springSmooth, value: UUID())
    }
}
