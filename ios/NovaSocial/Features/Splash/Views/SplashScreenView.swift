import SwiftUI

struct SplashScreenView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var isActive = false

    var body: some View {
        ZStack {
            // 背景色
            DesignTokens.accentColor
                .ignoresSafeArea()

            // Icered 图标
            Image("Icered-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .foregroundColor(.white)
        }
        .task {
            // 1.5秒后检查登录状态并跳转
            do {
                try await Task.sleep(for: .seconds(1.5))

                // 检查是否已登录
                if authManager.isAuthenticated {
                    // 已登录，直接进入主页
                    currentPage = .home
                } else {
                    // 未登录，跳转到登录页
                    currentPage = .login
                }
            } catch {
                // Task cancelled
            }
        }
    }
}

// MARK: - Previews

#Preview("Splash - Default") {
    SplashScreenView(currentPage: .constant(.splash))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Splash - Dark Mode") {
    SplashScreenView(currentPage: .constant(.splash))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
