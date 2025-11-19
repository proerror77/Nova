import SwiftUI

@main
struct FigmaDesignAppApp: App {
    @State private var currentPage: AppPage = .home

    init() {
        // Enable mock authentication for testing
        // TODO: Remove this once real authentication is implemented
        APIClient.shared.enableMockAuth()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 根据状态即时切换页面（无过渡动画）
                switch currentPage {
                case .home:
                    HomeView(currentPage: $currentPage)
                        .transition(.identity)
                case .message:
                    MessageView(currentPage: $currentPage)
                        .transition(.identity)
                case .account:
                    ProfileView(currentPage: $currentPage)
                        .transition(.identity)
                default:
                    HomeView(currentPage: $currentPage)
                        .transition(.identity)
                }
            }
            .animation(.none, value: currentPage)
        }
    }
}
