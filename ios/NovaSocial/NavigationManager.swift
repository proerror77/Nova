import SwiftUI

/// 全局导航管理器
/// 负责管理应用的导航栈，提供 push、pop 等基础导航操作
@Observable
final class NavigationManager {
    var path: NavigationPath = NavigationPath()

    /// 推送一个新的导航目的地
    /// - Parameter destination: 目的地标识符（字符串）
    func push(_ destination: String) {
        path.append(destination)
    }

    /// 弹出当前视图，返回上一页
    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    /// 返回到根视图
    func popToRoot() {
        path = NavigationPath()
    }

    /// 检查导航栈是否为空
    var isEmpty: Bool {
        path.isEmpty
    }

    /// 获取导航栈的深度
    var depth: Int {
        path.count
    }
}
