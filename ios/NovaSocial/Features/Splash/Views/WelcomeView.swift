import SwiftUI

struct WelcomeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager

    var body: some View {
        ZStack {
            // 背景图片（水平翻转，布满整个页面）
            GeometryReader { geometry in
                Image("welcome-bg")
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: -1, y: 1)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }

            // Icon
            VStack {
                Spacer()
                    .frame(height: 288.h)

                ZStack {
                    Image("Login-Icon")
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: 84.s, height: 52.s)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 145.w)

            // Welcome Text
            VStack {
                Spacer()
                    .frame(height: 370.h)

                Text("WELCOME TO ICERED")
                    .font(Font.custom("SFProDisplay-Bold", size: 24.f))
                    .tracking(1.20)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 56.w)

            // Subtitle Text
            VStack {
                Spacer()
                    .frame(height: 414.h)

                Text("An exclusive social platform\nfor global executives and decision\nmakers.")
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                    .tracking(0.80)
                    .lineSpacing(8)
                    .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36.w)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .task {
            // 显示 2 秒后清除标记并跳转到 Home
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                // Handle task cancellation gracefully
                print("[Welcome] ⚠️ Task cancelled: \(error)")
                return
            }
            
            // Clear the first-time registration flag
            UserDefaults.standard.set(false, forKey: "shouldShowWelcome")
            print("[Welcome] ✅ First-time welcome shown, navigating to home")
            currentPage = .home
        }
    }
}

// MARK: - Previews

#Preview("Welcome") {
    @Previewable @State var currentPage: AppPage = .welcome
    WelcomeView(currentPage: $currentPage)
        .environmentObject(AuthenticationManager.shared)
}
