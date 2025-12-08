import SwiftUI

struct NotificationView: View {
    @Binding var showNotification: Bool
    @State private var showChat = false
    @State private var selectedUserName = ""
    @State private var selectedConversationId = ""

    var body: some View {
        ZStack {
            // 条件渲染：根据状态切换视图
            if showChat {
                ChatView(showChat: $showChat, conversationId: selectedConversationId, userName: selectedUserName)
                    .transition(.identity)
            } else {
                notificationContent
            }
        }
        .animation(.none, value: showChat)
    }

    private var notificationContent: some View {
        ZStack {
            // MARK: - 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 返回按钮
                    Button(action: {
                        showNotification = false
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    // 标题
                    Text("Notification")
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)

                // 分隔线
                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                // MARK: - 通知列表
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Today Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Today")
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                .foregroundColor(DesignTokens.textPrimary)
                                .padding(.horizontal, 16)

                            NotificationListItem(
                                userName: "Ethan Miller",
                                action: "Go for your job.",
                                time: "4d",
                                buttonType: .message,
                                onMessageTap: {
                                    selectedUserName = "Ethan Miller"
                                    // TODO: Get actual conversation ID from API
                                    selectedConversationId = "notification_conv_ethan_miller"
                                    showChat = true
                                }
                            )
                        }

                        // Last 7 Days Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Last 7 Days")
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                .foregroundColor(DesignTokens.textPrimary)
                                .padding(.horizontal, 16)

                            NotificationListItem(
                                userName: "Lucas",
                                action: "liked your post.",
                                time: "4d",
                                buttonType: .followBack
                            )

                            NotificationListItem(
                                userName: "Noah Carter",
                                action: "liked your post.",
                                time: "4d",
                                buttonType: .follow
                            )

                            NotificationListItem(
                                userName: "Oliver Hayes",
                                action: "liked your post.",
                                time: "4d",
                                buttonType: .follow
                            )

                            NotificationListItem(
                                userName: "Liam Foster",
                                action: "liked your post.",
                                time: "4d",
                                buttonType: .follow
                            )
                        }

                        // Last 30 Days Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Last 30 Days")
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                .foregroundColor(DesignTokens.textPrimary)
                                .padding(.horizontal, 16)

                            NotificationListItem(
                                userName: "Ava Turner",
                                action: "liked your post.",
                                time: "4w",
                                buttonType: .followBack
                            )

                            NotificationListItem(
                                userName: "Sophia Reed",
                                action: "liked your post.",
                                time: "4w",
                                buttonType: .follow
                            )

                            NotificationListItem(
                                userName: "Sophia Reed",
                                action: "liked your post.",
                                time: "4w",
                                buttonType: .follow
                            )

                            NotificationListItem(
                                userName: "Sophia Reed",
                                action: "liked your post.",
                                time: "4w",
                                buttonType: .follow
                            )

                            NotificationListItem(
                                userName: "Sophia Reed",
                                action: "liked your post.",
                                time: "4w",
                                buttonType: .follow
                            )
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

// MARK: - 按钮类型枚举
enum NotificationButtonType {
    case message
    case follow
    case followBack
    case none
}

// MARK: - 通知列表项组件
struct NotificationListItem: View {
    let userName: String
    let action: String
    let time: String
    let buttonType: NotificationButtonType
    var onMessageTap: (() -> Void)?
    @State private var isFollowing = false

    var body: some View {
        HStack(spacing: 13) {
            // 头像 - 42x42
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 42, height: 42)

            // 内容
            VStack(alignment: .leading, spacing: 1) {
                Text(userName)
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                    .foregroundColor(DesignTokens.textPrimary)

                HStack(spacing: 4) {
                    Text(action)
                        .font(Font.custom("Helvetica Neue", size: 14))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(time)
                        .font(Font.custom("Helvetica Neue", size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }
            }

            Spacer()

            // 按钮
            switch buttonType {
            case .message:
                Button(action: {
                    onMessageTap?()
                }) {
                    Text("Message")
                        .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                        .foregroundColor(DesignTokens.textPrimary)
                }
                .frame(width: 85, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .inset(by: 0.50)
                        .stroke(DesignTokens.textPrimary, lineWidth: 0.50)
                )

            case .follow:
                Button(action: {
                    isFollowing.toggle()
                }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
                .frame(width: 85, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .inset(by: 0.50)
                        .stroke(Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.50)
                )

            case .followBack:
                Button(action: {
                    isFollowing.toggle()
                }) {
                    Text(isFollowing ? "Following" : "Follow back")
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
                .frame(width: 85, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 100)
                        .inset(by: 0.50)
                        .stroke(Color(red: 0.87, green: 0.11, blue: 0.26), lineWidth: 0.50)
                )

            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.surface)
    }
}

#Preview {
    NotificationView(showNotification: .constant(true))
}
