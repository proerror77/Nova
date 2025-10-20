import SwiftUI

/// 设计系统 Toast 通知组件
/// Design System Toast Notification Component
public struct DSToast: View {

    // MARK: - Toast Style

    public enum Style {
        case success
        case error
        case warning
        case info

        var color: (AppTheme) -> Color {
            switch self {
            case .success: return { $0.colors.success }
            case .error: return { $0.colors.error }
            case .warning: return { $0.colors.warning }
            case .info: return { $0.colors.info }
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    // MARK: - Position

    public enum Position {
        case top
        case center
        case bottom

        var alignment: Alignment {
            switch self {
            case .top: return .top
            case .center: return .center
            case .bottom: return .bottom
            }
        }

        var edge: Edge {
            switch self {
            case .top: return .top
            case .center: return .top
            case .bottom: return .bottom
            }
        }

        var offset: CGFloat {
            switch self {
            case .top: return 60
            case .center: return 0
            case .bottom: return -60
            }
        }
    }

    // MARK: - Properties

    @Environment(\.appTheme) private var theme

    private let message: String
    private let style: Style
    private let icon: String?
    private let duration: Double
    private let onDismiss: (() -> Void)?

    // MARK: - Initialization

    public init(
        message: String,
        style: Style = .info,
        icon: String? = nil,
        duration: Double = 3.0,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.style = style
        self.icon = icon
        self.duration = duration
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: icon ?? style.icon)
                .font(.system(size: DesignTokens.IconSize.md))
                .foregroundColor(.white)

            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .background(style.color(theme))
        .cornerRadius(DesignTokens.BorderRadius.md)
        .shadow(
            color: style.color(theme).opacity(0.3),
            radius: 8,
            x: 0,
            y: 4
        )
        .padding(.horizontal, DesignTokens.Spacing.md)
    }
}

// MARK: - Toast Manager

/// Toast 通知管理器
@MainActor
public final class ToastManager: ObservableObject {

    // MARK: - Toast Item

    public struct ToastItem: Identifiable {
        public let id = UUID()
        let message: String
        let style: DSToast.Style
        let icon: String?
        let duration: Double
        let position: DSToast.Position

        public init(
            message: String,
            style: DSToast.Style = .info,
            icon: String? = nil,
            duration: Double = 3.0,
            position: DSToast.Position = .top
        ) {
            self.message = message
            self.style = style
            self.icon = icon
            self.duration = duration
            self.position = position
        }
    }

    // MARK: - Singleton

    public static let shared = ToastManager()

    // MARK: - Published Properties

    @Published public private(set) var currentToast: ToastItem?

    // MARK: - Private Properties

    private var workItem: DispatchWorkItem?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 显示 Toast
    public func show(
        _ message: String,
        style: DSToast.Style = .info,
        icon: String? = nil,
        duration: Double = 3.0,
        position: DSToast.Position = .top
    ) {
        // 取消之前的定时器
        workItem?.cancel()

        // 显示新 Toast
        currentToast = ToastItem(
            message: message,
            style: style,
            icon: icon,
            duration: duration,
            position: position
        )

        // 设置自动隐藏
        let task = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        workItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    /// 显示成功 Toast
    public func success(_ message: String, duration: Double = 3.0, position: DSToast.Position = .top) {
        show(message, style: .success, duration: duration, position: position)
    }

    /// 显示错误 Toast
    public func error(_ message: String, duration: Double = 3.0, position: DSToast.Position = .top) {
        show(message, style: .error, duration: duration, position: position)
    }

    /// 显示警告 Toast
    public func warning(_ message: String, duration: Double = 3.0, position: DSToast.Position = .top) {
        show(message, style: .warning, duration: duration, position: position)
    }

    /// 显示信息 Toast
    public func info(_ message: String, duration: Double = 3.0, position: DSToast.Position = .top) {
        show(message, style: .info, duration: duration, position: position)
    }

    /// 隐藏 Toast
    public func dismiss() {
        withAnimation(Animations.standard) {
            currentToast = nil
        }
        workItem?.cancel()
        workItem = nil
    }
}

// MARK: - Toast Container View

/// Toast 容器视图
struct ToastContainerModifier: ViewModifier {

    @ObservedObject var toastManager: ToastManager
    @State private var offset: CGFloat = -100

    func body(content: Content) -> some View {
        ZStack(alignment: toastManager.currentToast?.position.alignment ?? .top) {
            content

            if let toast = toastManager.currentToast {
                DSToast(
                    message: toast.message,
                    style: toast.style,
                    icon: toast.icon,
                    onDismiss: { toastManager.dismiss() }
                )
                .offset(y: toast.position.offset)
                .transition(.move(edge: toast.position.edge).combined(with: .opacity))
                .animation(Animations.spring, value: toastManager.currentToast?.id)
                .zIndex(DesignTokens.ZIndex.toast)
                .onTapGesture {
                    toastManager.dismiss()
                }
            }
        }
    }
}

// MARK: - View Extension

extension View {

    /// 添加 Toast 支持
    public func withToast() -> some View {
        modifier(ToastContainerModifier(toastManager: ToastManager.shared))
    }
}

// MARK: - Previews

#if DEBUG
struct DSToast_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            DSToast(message: "操作成功！", style: .success)
            DSToast(message: "发生错误，请稍后重试", style: .error)
            DSToast(message: "请注意，这是一个警告信息", style: .warning)
            DSToast(message: "这是一条普通信息通知", style: .info)

            Divider()

            VStack(spacing: DesignTokens.Spacing.md) {
                DSButton("显示成功 Toast", style: .primary) {
                    ToastManager.shared.success("操作成功！")
                }

                DSButton("显示错误 Toast", style: .destructive) {
                    ToastManager.shared.error("发生错误")
                }

                DSButton("显示警告 Toast", style: .secondary) {
                    ToastManager.shared.warning("请注意")
                }

                DSButton("显示信息 Toast", style: .ghost) {
                    ToastManager.shared.info("普通消息")
                }
            }
        }
        .padding()
        .withToast()
        .withThemeManager()
        .previewDisplayName("Toasts")
    }
}
#endif
