//
//  AccessibilityModifiers.swift
//  NovaSocial
//
//  可访问性核心修饰符 - Linus 式简洁设计
//  三个核心 modifier 解决 90% 的可访问性问题
//

import SwiftUI

// MARK: - 核心可访问性修饰符

extension View {
    /// 最小触控区域修饰符 (44x44pt Apple 标准)
    /// 用法: Button("确定") { }.minTouchTarget()
    func minTouchTarget(width: CGFloat = 44, height: CGFloat = 44) -> some View {
        self.frame(minWidth: width, minHeight: height)
            .contentShape(Rectangle())
    }

    /// VoiceOver 完整支持
    /// 用法: Image("avatar").voiceOverSupport(label: "用户头像", hint: "双击查看资料")
    func voiceOverSupport(
        label: String,
        hint: String? = nil,
        value: String? = nil,
        traits: AccessibilityTraits = [],
        hidden: Bool = false
    ) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(traits)
            .accessibilityHidden(hidden)
    }

    /// 动态文字大小支持 (Dynamic Type)
    /// 用法: Text("标题").dynamicTypeSupport(style: .title)
    func dynamicTypeSupport(
        style: Font.TextStyle = .body,
        minScale: CGFloat = 0.8,
        maxScale: CGFloat = 2.0
    ) -> some View {
        self
            .font(.system(style, design: .default))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .minimumScaleFactor(minScale)
    }
}

// MARK: - 语义化按钮

struct AccessibleButton<Label: View>: View {
    let label: String
    let hint: String?
    let action: () -> Void
    let buttonLabel: () -> Label

    init(
        _ label: String,
        hint: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder buttonLabel: @escaping () -> Label
    ) {
        self.label = label
        self.hint = hint
        self.action = action
        self.buttonLabel = buttonLabel
    }

    var body: some View {
        Button(action: action) {
            buttonLabel()
        }
        .voiceOverSupport(
            label: label,
            hint: hint,
            traits: .isButton
        )
        .minTouchTarget()
    }
}

// MARK: - 图片可访问性

extension Image {
    /// 装饰性图片 (VoiceOver 会跳过)
    func decorative() -> some View {
        self.accessibilityHidden(true)
    }

    /// 有意义的图片 (VoiceOver 会读出描述)
    func meaningful(_ description: String) -> some View {
        self.voiceOverSupport(
            label: description,
            traits: .isImage
        )
    }
}

// MARK: - 列表可访问性

extension List {
    /// 优化 VoiceOver 列表朗读顺序
    func accessibleList() -> some View {
        self.accessibilityElement(children: .contain)
    }
}

// MARK: - 文本可访问性

extension Text {
    /// 标题文本 (大号、粗体、高对比度)
    func accessibleTitle() -> some View {
        self
            .font(.title)
            .fontWeight(.bold)
            .dynamicTypeSupport(style: .title)
            .foregroundColor(.primary)
    }

    /// 正文文本 (标准大小、可缩放)
    func accessibleBody() -> some View {
        self
            .dynamicTypeSupport(style: .body)
            .foregroundColor(.primary)
    }

    /// 副标题文本 (次要信息)
    func accessibleCaption() -> some View {
        self
            .dynamicTypeSupport(style: .caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - 动画安全 (Reduce Motion)

extension View {
    /// 尊重 Reduce Motion 设置的动画
    /// 用法: view.safeAnimation(.spring(), value: state)
    @ViewBuilder
    func safeAnimation<V: Equatable>(
        _ animation: Animation,
        value: V
    ) -> some View {
        if AccessibilitySettings.reduceMotion {
            self
        } else {
            self.animation(animation, value: value)
        }
    }

    /// 尊重 Reduce Motion 设置的过渡效果
    @ViewBuilder
    func safeTransition(_ transition: AnyTransition) -> some View {
        if AccessibilitySettings.reduceMotion {
            self
        } else {
            self.transition(transition)
        }
    }
}

// MARK: - 可访问性设置检测

enum AccessibilitySettings {
    /// 是否启用了减少动画
    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// 是否启用了 VoiceOver
    static var isVoiceOverRunning: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    /// 是否启用了粗体文本
    static var isBoldTextEnabled: Bool {
        UIAccessibility.isBoldTextEnabled
    }

    /// 是否启用了增强对比度
    static var isDarkerSystemColorsEnabled: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled
    }

    /// 当前动态文字大小
    static var preferredContentSizeCategory: UIContentSizeCategory {
        UIApplication.shared.preferredContentSizeCategory
    }
}

// MARK: - 颜色对比度辅助

extension Color {
    /// 确保文本在背景上有足够对比度
    /// 用法: Color.primary.withMinimumContrast(on: .white)
    func withMinimumContrast(on background: Color) -> Color {
        // 简单实现:如果背景是浅色,返回深色文本,反之亦然
        // 生产环境应使用 WCAG 对比度算法
        let isLightBackground = background == .white || background == Color(.systemBackground)
        return isLightBackground ? .black : .white
    }
}

// MARK: - 焦点管理 (键盘导航)

extension View {
    /// 设置为可聚焦元素 (支持键盘导航)
    func keyboardFocusable() -> some View {
        self.focusable()
    }
}

// MARK: - 表单可访问性

struct AccessibleTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .accessibleCaption()

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .voiceOverSupport(
                    label: label,
                    hint: placeholder,
                    value: text.isEmpty ? "未填写" : text
                )
                .minTouchTarget(height: 44)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .voiceOverSupport(
                        label: "错误: \(error)",
                        traits: .staticText
                    )
            }
        }
    }
}

// MARK: - 自定义 VoiceOver 操作

extension View {
    /// 添加自定义 VoiceOver 操作
    /// 用法: PostCell().customVoiceOverActions([.like, .comment, .share])
    func customVoiceOverActions(_ actions: [CustomVoiceOverAction]) -> some View {
        var view = self
        for action in actions {
            view = view.accessibilityAction(named: action.name) {
                action.handler()
            } as! Self
        }
        return view
    }
}

struct CustomVoiceOverAction {
    let name: Text
    let handler: () -> Void

    static func like(handler: @escaping () -> Void) -> CustomVoiceOverAction {
        CustomVoiceOverAction(name: Text("点赞"), handler: handler)
    }

    static func comment(handler: @escaping () -> Void) -> CustomVoiceOverAction {
        CustomVoiceOverAction(name: Text("评论"), handler: handler)
    }

    static func share(handler: @escaping () -> Void) -> CustomVoiceOverAction {
        CustomVoiceOverAction(name: Text("分享"), handler: handler)
    }

    static func follow(handler: @escaping () -> Void) -> CustomVoiceOverAction {
        CustomVoiceOverAction(name: Text("关注"), handler: handler)
    }
}

// MARK: - 可访问性调试工具

#if DEBUG
struct AccessibilityDebugView: View {
    var body: some View {
        List {
            Section("系统设置") {
                LabeledContent("VoiceOver", value: AccessibilitySettings.isVoiceOverRunning ? "开启" : "关闭")
                LabeledContent("减少动画", value: AccessibilitySettings.reduceMotion ? "开启" : "关闭")
                LabeledContent("粗体文本", value: AccessibilitySettings.isBoldTextEnabled ? "开启" : "关闭")
                LabeledContent("增强对比度", value: AccessibilitySettings.isDarkerSystemColorsEnabled ? "开启" : "关闭")
            }

            Section("文字大小") {
                Text("示例文字 - Extra Small")
                    .dynamicTypeSupport(style: .caption2)
                Text("示例文字 - Small")
                    .dynamicTypeSupport(style: .caption)
                Text("示例文字 - Body")
                    .dynamicTypeSupport(style: .body)
                Text("示例文字 - Large")
                    .dynamicTypeSupport(style: .title3)
                Text("示例文字 - Extra Large")
                    .dynamicTypeSupport(style: .title)
            }

            Section("按钮触控区域测试") {
                HStack {
                    Button("小按钮") { }
                        .font(.caption)

                    Button("标准按钮") { }
                        .minTouchTarget()
                }
            }
        }
        .navigationTitle("可访问性调试")
    }
}
#endif
