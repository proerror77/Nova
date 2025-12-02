import SwiftUI

// MARK: - Global Keyboard Dismiss Function

/// 全局隐藏键盘函数
func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

// MARK: - Keyboard Dismiss Extension

extension View {
    /// 点击空白处隐藏键盘
    /// 使用方法：在视图上添加 .dismissKeyboardOnTap()
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            hideKeyboard()
        }
    }
}

// MARK: - Keyboard Dismiss Modifier

/// 可配置的键盘隐藏修饰器
struct DismissKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
    }
}
