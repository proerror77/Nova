import SwiftUI

struct ChatView: View {
    @Binding var showChat: Bool
    @State private var messageText = ""
    @State private var showUserProfile = false

    var body: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 13) {
                    // 返回按钮
                    Button(action: {
                        showChat = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black)
                    }

                    // 头像和用户名 - 可点击跳转到用户资料
                    HStack(spacing: 13) {
                        // 头像
                        Circle()
                            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                            .frame(width: 50, height: 50)

                        // 用户名
                        Text("Eli")
                            .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                            .foregroundColor(.black)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            showUserProfile = true
                        }
                    }

                    Spacer()
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                // 分隔线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                // MARK: - 聊天消息区域
                ScrollView {
                    VStack(spacing: 16) {
                        // 时间戳
                        Text("2025/10/22  12:00")
                            .font(Font.custom("Helvetica Neue", size: 12))
                            .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                            .padding(.top, 16)

                        // 对方消息 1
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                .frame(width: 50, height: 50)

                            Text("Hello, how are you bro~")
                                .font(Font.custom("Helvetica Neue", size: 18))
                                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                                .cornerRadius(23)

                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // 对方消息 2
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                .frame(width: 50, height: 50)

                            Text("miss you")
                                .font(Font.custom("Helvetica Neue", size: 18))
                                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                                .cornerRadius(23)

                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // 我的消息
                        HStack(spacing: 6) {
                            Spacer()

                            Text("Uh-huh...")
                                .font(Font.custom("Helvetica Neue", size: 18))
                                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                                .cornerRadius(23)

                            Circle()
                                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                .frame(width: 50, height: 50)
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // MARK: - 底部输入区域
                VStack(spacing: 0) {
                    // 分隔线
                    Divider()
                        .frame(height: 0.5)
                        .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                    HStack(spacing: 12) {
                        // 添加按钮
                        Button(action: {}) {
                            ZStack {
                                Circle()
                                    .stroke(Color(red: 0.91, green: 0.18, blue: 0.30), lineWidth: 2)
                                    .frame(width: 26, height: 26)

                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color(red: 0.91, green: 0.18, blue: 0.30))
                            }
                        }

                        // 输入框
                        HStack(spacing: 8) {
                            // 语音图标
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                            // 文本输入框
                            TextField("", text: $messageText)
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                        }
                        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .background(Color(red: 0.53, green: 0.53, blue: 0.53).opacity(0.20))
                        .cornerRadius(26)

                        // 发送按钮
                        Button(action: {
                            // 发送消息
                        }) {
                            Circle()
                                .fill(Color(red: 0.91, green: 0.18, blue: 0.30))
                                .frame(width: 33, height: 33)
                                .overlay(
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                }
            }
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            UserProfileView(showUserProfile: $showUserProfile)
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }
}

#Preview {
    ChatView(showChat: .constant(true))
}
