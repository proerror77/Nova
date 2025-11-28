import SwiftUI

struct WelcomeView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            // 背景图片
            GeometryReader { geometry in
                Image("Login-Background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .edgesIgnoringSafeArea(.all)

            // Dark overlay to dim the background
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ICERED Logo Icon
                Image("Login-Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 90)
                    .padding(.bottom, 60)

                // Welcome to Icered 标题
                Text("Welcome to Icered")
                    .font(Font.custom("Helvetica Neue", size: 24).weight(.bold))
                    .lineSpacing(46)
                    .foregroundColor(.white)
                    .padding(.bottom, 20)

                // 副标题
                Text("\"For the masters of the universe.\"")
                    .font(Font.custom("Helvetica Neue", size: 20).weight(.thin))
                    .tracking(1)
                    .lineSpacing(27)
                    .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                // Get started 按钮
                Button(action: {
                    currentPage = .login
                }) {
                    Text("Get started")
                        .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                        .lineSpacing(20)
                        .foregroundColor(.white)
                        .frame(width: 343, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 31.50)
                                .inset(by: 0.50)
                                .stroke(.white, lineWidth: 0.50)
                        )
                }
                .padding(.bottom, 60)
            }
        }
    }
}

#Preview {
    WelcomeView(currentPage: .constant(.welcome))
}
