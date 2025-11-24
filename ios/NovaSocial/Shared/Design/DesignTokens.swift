import SwiftUI
import UIKit

// MARK: - Design Tokens
/// 统一的设计规范，供所有页面使用
/// 支持亮色和暗色两种主题模式
struct DesignTokens {
    // MARK: - Dynamic Colors (响应主题切换)

    /// 主背景色
    static func backgroundColor(isDark: Bool) -> Color {
        isDark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.97, green: 0.96, blue: 0.96)
        // Light: #F8F7F7, Dark: #1C1C1E
    }

    /// 卡片/容器背景色
    static func cardBackground(isDark: Bool) -> Color {
        isDark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white
        // Light: #FFFFFF, Dark: #2C2C2E
    }

    /// 主文本颜色
    static func textPrimary(isDark: Bool) -> Color {
        isDark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.38, green: 0.37, blue: 0.37)
        // Light: #616060, Dark: #F2F2F7
    }

    /// 次要文本颜色
    static func textSecondary(isDark: Bool) -> Color {
        isDark ? Color(red: 0.68, green: 0.68, blue: 0.70) : Color(red: 0.68, green: 0.68, blue: 0.68)
        // Light: #ADADAD, Dark: #AEAEB2
    }

    /// 品牌主题色（红色）
    static func accentColor(isDark: Bool) -> Color {
        isDark ? Color(red: 1, green: 0.27, blue: 0.33) : Color(red: 0.82, green: 0.13, blue: 0.25)
        // Light: #D11F40, Dark: #FF4555 (稍微提亮以提高对比度)
    }

    /// 品牌色浅色版本
    static func accentLight(isDark: Bool) -> Color {
        isDark ? Color(red: 0.82, green: 0.13, blue: 0.25).opacity(0.3) : Color(red: 1, green: 0.78, blue: 0.78)
        // Light: #FFC7C7, Dark: rgba(210, 31, 64, 0.3)
    }

    /// 边框颜色
    static func borderColor(isDark: Bool) -> Color {
        isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.74, green: 0.74, blue: 0.74)
        // Light: #BDBDBD, Dark: #3A3A3C
    }

    /// 占位符颜色
    static func placeholderColor(isDark: Bool) -> Color {
        isDark ? Color(red: 0.35, green: 0.35, blue: 0.36) : Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
        // Light: rgba(128, 59, 69, 0.5), Dark: #595959
    }

    /// 分隔线颜色
    static func dividerColor(isDark: Bool) -> Color {
        isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.93, green: 0.93, blue: 0.93)
        // Light: #EDEDED, Dark: #3A3A3C
    }

    // MARK: - Legacy Static Colors (向后兼容，建议逐步迁移到动态颜色)

    static let backgroundColor = Color(red: 0.97, green: 0.96, blue: 0.96)
    static let white = Color.white
    static let textPrimary = Color(red: 0.38, green: 0.37, blue: 0.37)
    static let textSecondary = Color(red: 0.68, green: 0.68, blue: 0.68)
    static let accentColor = Color(red: 0.82, green: 0.13, blue: 0.25)
    static let accentLight = Color(red: 1, green: 0.78, blue: 0.78)
    static let borderColor = Color(red: 0.74, green: 0.74, blue: 0.74)
    static let placeholderColor = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)

    // MARK: - Spacing

    static let spacing8: CGFloat = 8
    static let spacing16: CGFloat = 16
    static let spacing13: CGFloat = 13

    // MARK: - Sizes

    static let tagWidth: CGFloat = 173.36
    static let tagHeight: CGFloat = 30.80
    static let avatarSize: CGFloat = 38
    static let topBarHeight: CGFloat = 56  // 统一的顶部导航栏高度（与 HomeView 一致）

    // MARK: - Convenient Color Properties (自动跟随主题)
    // 使用这些便捷属性，无需手动传递 isDark 参数

    /// 主背景色（自动跟随主题）
    @MainActor
    static var background: Color {
        backgroundColor(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 卡片/容器背景色（自动跟随主题）
    @MainActor
    static var card: Color {
        cardBackground(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 主文本颜色（自动跟随主题）
    @MainActor
    static var text: Color {
        textPrimary(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 次要文本颜色（自动跟随主题）
    @MainActor
    static var textLight: Color {
        textSecondary(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 品牌主题色（自动跟随主题）
    @MainActor
    static var accent: Color {
        accentColor(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 品牌色浅色版本（自动跟随主题）
    @MainActor
    static var accentLightColor: Color {
        accentLight(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 边框颜色（自动跟随主题）
    @MainActor
    static var border: Color {
        borderColor(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 占位符颜色（自动跟随主题）
    @MainActor
    static var placeholder: Color {
        placeholderColor(isDark: ThemeManager.shared.isDarkMode)
    }

    /// 分隔线颜色（自动跟随主题）
    @MainActor
    static var divider: Color {
        dividerColor(isDark: ThemeManager.shared.isDarkMode)
    }
}

// MARK: - Theme Manager
/// 主题管理器 - 管理应用的亮色/暗色模式
/// 使用 @Observable 提供响应式主题切换
@Observable
final class ThemeManager {
    // MARK: - Singleton

    @MainActor
    static let shared = ThemeManager()

    // MARK: - Properties

    /// 当前是否为暗色模式
    var isDarkMode: Bool {
        didSet {
            // 持久化到 UserDefaults
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }

    // MARK: - Initialization

    private init() {
        // 从 UserDefaults 加载保存的主题偏好
        self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
    }

    // MARK: - Public Methods

    /// 切换主题模式
    func toggleTheme() {
        isDarkMode.toggle()
    }

    /// 设置主题模式
    func setTheme(dark: Bool) {
        isDarkMode = dark
    }

    // MARK: - Color Scheme

    /// 获取当前的 ColorScheme
    var colorScheme: ColorScheme {
        isDarkMode ? .dark : .light
    }
}

// MARK: - CameraPicker
/// 相机选择器 - 包装 UIImagePickerController 用于拍照
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImageCaptured: ((UIImage) -> Void)?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured?(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
