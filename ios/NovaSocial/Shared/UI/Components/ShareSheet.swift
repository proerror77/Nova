import SwiftUI
import UIKit

// MARK: - Share Sheet Component

/// iOS 原生分享面板组件
/// 使用 UIActivityViewController 实现系统级分享功能
struct NovaShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Share Sheet Modifier

extension View {
    /// 添加分享功能的便捷方法
    /// - Parameters:
    ///   - isPresented: 控制分享面板显示/隐藏的绑定
    ///   - items: 要分享的内容数组
    func shareSheet(isPresented: Binding<Bool>, items: [Any]) -> some View {
        self.sheet(isPresented: isPresented) {
            NovaShareSheet(items: items)
        }
    }
}
