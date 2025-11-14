import SwiftUI

struct MessageView: View {
    @Binding var currentPage: AppPage
    @State private var showNewPost = false
    @State private var showChat = false

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showChat {
                ChatView(showChat: $showChat)
                    .transition(.identity)
            } else if showNewPost {
                NewPostView(showNewPost: $showNewPost)
                    .transition(.identity)
            } else {
                messageContent
            }
        }
        .animation(.none, value: showChat)
        .animation(.none, value: showNewPost)
    }

    // MARK: - 消息页面内容
    private var messageContent: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Spacer()

                    Text("Message")
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 右侧添加按钮 (圆圈加号)
                    Button(action: {}) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.black)
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                // MARK: - 顶部分割线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Text("Search")
                        .font(Font.custom("Helvetica Neue", size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - 消息列表
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(0..<9, id: \.self) { index in
                            MessageListItem()
                                .onTapGesture {
                                    showChat = true
                                }

                            if index < 8 {
                                Divider()
                                    .frame(height: 0.25)
                                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))
                            }
                        }
                    }
                }
                .padding(.bottom, -43)

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black)
                    }
                     .frame(maxWidth: .infinity)
                     .onTapGesture {
                         currentPage = .home
                     }

                    // Message (高亮状态)
                    VStack(spacing: 4) {
                        Image("Message-icon-red")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Message")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                    .frame(maxWidth: .infinity)

                    // New Post
                    NewPostButtonComponent(showNewPost: $showNewPost)

                    // Alice
                    VStack(spacing: -12) {
                        Image("alice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)

                    // Account
                    VStack(spacing: 4) {
                        Image("Account-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
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
    }
}

// MARK: - 消息列表项组件
struct MessageListItem: View {
    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 63, height: 63)

            // 消息内容
            VStack(alignment: .leading, spacing: 5) {
                Text("Liam")
                    .font(Font.custom("Helvetica Neue", size: 19).weight(.bold))
                    .foregroundColor(.black)

                Text("Hello, how are you bro~")
                    .font(Font.custom("Helvetica Neue", size: 15))
                    .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
            }

            Spacer()

            // 时间和未读标记
            VStack(alignment: .trailing, spacing: 6) {
                Text("09:41 PM")
                    .font(Font.custom("Helvetica Neue", size: 13))
                    .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))

                ZStack {
                    Circle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 17, height: 17)

                    Text("1")
                        .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(EdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18))
        .frame(height: 80)
        .background(Color(red: 0.97, green: 0.96, blue: 0.96))
    }
}

#Preview {
    MessageView(currentPage: .constant(.message))
}
