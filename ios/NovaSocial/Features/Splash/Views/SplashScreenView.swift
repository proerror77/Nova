import SwiftUI

struct SplashScreenView: View {
    @Binding var currentPage: AppPage
    @State private var isActive = false

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.87, green: 0.11, blue: 0.26)
                .ignoresSafeArea()

            // ICERED 文字
            Text("ICERED")
                .font(.system(size: 48, weight: .medium, design: .default))
                .foregroundColor(.white)
                .tracking(8)
                .kerning(8)
        }
        .task {
            // 3秒后自动跳转到登录页面
            do {
                try await Task.sleep(for: .seconds(3))
                currentPage = .login
            } catch {
                // Task cancelled
            }
        }
    }
}

#Preview {
    SplashScreenView(currentPage: .constant(.splash))
}
