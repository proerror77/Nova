import SwiftUI

@main
struct FigmaDesignAppApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var currentPage: AppPage = .home

    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                // Main app - authenticated user
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
            } else {
                // Login screen - not authenticated
                LoginView()
            }
        }
    }
}
