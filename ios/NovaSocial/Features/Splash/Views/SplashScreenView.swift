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

            // ICERED 文字
            Text("ICERED")
                .font(.system(size: 48, weight: .medium, design: .default))
                .foregroundColor(.white)
                .tracking(8)
                .kerning(8)
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

#Preview {
    SplashScreenView(currentPage: .constant(.splash))
}
