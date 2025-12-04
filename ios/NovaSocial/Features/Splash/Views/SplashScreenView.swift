import SwiftUI

struct SplashScreenView: View {
    @Binding var currentPage: AppPage
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
            // 1.5秒后自动跳转到欢迎页面
            do {
                try await Task.sleep(for: .seconds(1.5))
                currentPage = .welcome
            } catch {
                // Task cancelled
            }
        }
    }
}

#Preview {
    SplashScreenView(currentPage: .constant(.splash))
}
