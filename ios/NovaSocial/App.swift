import SwiftUI

@main
struct FigmaDesignAppApp: App {
    @State private var currentPage: AppPage = .home

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 根据状态即时切换页面（无过渡动画）
                if currentPage == .home {
                    HomeView(currentPage: $currentPage)
                        .transition(.identity)
                } else {
                    MessageView(currentPage: $currentPage)
                        .transition(.identity)
                }
            }
            .animation(.none, value: currentPage)
        }
    }
}

// 页面枚举
enum AppPage {
    case home
    case message
}
