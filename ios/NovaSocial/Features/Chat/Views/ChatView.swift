import SwiftUI

struct ChatView: View {
    @Binding var showChat: Bool
    @State private var messageText = ""
    @State private var showUserProfile = false

    var body: some View {
        ZStack {
            // MARK: - 背景色
            DesignTokens.background
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
                            .foregroundColor(DesignTokens.text)
                    }

                    // 头像和用户名 - 可点击跳转到用户资料
                    HStack(spacing: 13) {
                        // 头像
                        Circle()
                            .fill(DesignTokens.placeholder)
                            .frame(width: 50, height: 50)

                        // 用户名
                        Text("Eli")
                            .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                            .foregroundColor(DesignTokens.text)
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
                .background(DesignTokens.card)

                // 分隔线
                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.border)

                // MARK: - 聊天消息区域
                ScrollView {
                    VStack(spacing: 16) {
                        // 时间戳
                        Text("2025/10/22  12:00")
                            .font(Font.custom("Helvetica Neue", size: 12))
                            .foregroundColor(DesignTokens.textLight)
                            .padding(.top, 16)

                        // 对方消息 1
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DesignTokens.placeholder)
                                .frame(width: 50, height: 50)

                            Text("Hello, how are you bro~")
                                .font(Font.custom("Helvetica Neue", size: 18))
                                .foregroundColor(DesignTokens.text)
                                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .background(DesignTokens.placeholder.opacity(0.2))
                                .cornerRadius(23)

                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // 对方消息 2
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DesignTokens.placeholder)
                                .frame(width: 50, height: 50)

                            Text("miss you")
                                .font(Font.custom("Helvetica Neue", size: 18))
                                .foregroundColor(DesignTokens.text)
                                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .background(DesignTokens.placeholder.opacity(0.2))
                                .cornerRadius(23)

                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // 我的消息
                        HStack(spacing: 6) {
                            Spacer()

                            Text("Uh-huh...")
                                .font(Font.custom("Helvetica Neue", size: 18))
                                .foregroundColor(DesignTokens.text)
                                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .background(DesignTokens.placeholder.opacity(0.2))
                                .cornerRadius(23)

                            Circle()
                                .fill(DesignTokens.placeholder)
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
                        .background(DesignTokens.border)

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
                                .foregroundColor(DesignTokens.textLight)

                            // 文本输入框
                            TextField("", text: $messageText)
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .foregroundColor(DesignTokens.text)
                        }
                        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .background(DesignTokens.placeholder.opacity(0.2))
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
                    .background(DesignTokens.card)
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
