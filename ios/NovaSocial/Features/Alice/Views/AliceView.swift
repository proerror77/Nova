import SwiftUI

struct AliceView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                topNavigationBar

                Spacer()

                // MARK: - 输入区域
                inputArea
                    .offset(y: -90)

                Spacer()
            }

            // MARK: - 底部导航栏 (使用绝对定位)
            VStack {
                Spacer()
                bottomNavigationBar
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - 顶部导航栏
    private var topNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 97) {
                // 返回按钮
                Button(action: {
                    currentPage = .home
                }) {
                    Image("back-black")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }

                // 标题
                Text("alice")
                    .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                    .lineSpacing(20)
                    .foregroundColor(.black)

                // 右侧占位
                Color.clear
                    .frame(width: 24, height: 24)
            }
            .frame(width: 343)
            .frame(height: 88)
            .background(.white)
        }
        .background(.white)
        .overlay(
            Rectangle()
                .inset(by: 0.20)
                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
        )
    }

    // MARK: - 输入区域
    private var inputArea: some View {
        ZStack(alignment: .bottomTrailing) {
            // 输入框背景
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 343, height: 126)
                .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .inset(by: 0.50)
                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.50)
                )

            // 发送按钮 (右下角)
            Button(action: {
                // 发送操作
            }) {
                Circle()
                    .fill(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .frame(width: 35, height: 35)
                    .overlay(
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                    )
            }
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 底部导航栏
    private var bottomNavigationBar: some View {
        HStack(spacing: -20) {
            // Home
            VStack(spacing: 4) {
                Image("Home-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("Home")
                    .font(.system(size: 9))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .home
            }

            // Message
            VStack(spacing: 4) {
                Image("Message-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("Message")
                    .font(.system(size: 9))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .message
            }

            // New Post (中间按钮)
            VStack(spacing: -10) {
                Image("Newpost")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 32)
                Text("")
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .newPost
            }

            // Alice (当前页面 - 高亮)
            VStack(spacing: -12) {
                Image("alice-button-on")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .frame(maxWidth: .infinity)

            // Account
            VStack(spacing: 4) {
                Image("Account-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("Account")
                    .font(.system(size: 9))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .account
            }
        }
        .frame(height: 60)
        .padding(.bottom, 20)
        .background(Color.white)
        .border(Color(red: 0.74, green: 0.74, blue: 0.74), width: 0.5)
        .offset(y: 35)
    }
}

#Preview {
    AliceView(currentPage: .constant(.alice))
}
