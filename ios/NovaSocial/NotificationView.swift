import SwiftUI

struct NotificationView: View {
    @Binding var showNotification: Bool

    var body: some View {
        ZStack {
            // MARK: - 背景色
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 返回按钮
                    Button(action: {
                        showNotification = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    // 标题
                    Text("Notification")
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                // 分隔线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                // MARK: - 通知列表
                ScrollView {
                    VStack(spacing: 0) {
                        // 通知项 1：点赞通知
                        NotificationListItem(
                            avatarColor: Color(red: 0.81, green: 0.13, blue: 0.25),
                            userName: "Liam",
                            action: "liked your post.",
                            time: "4d",
                            showFollowButton: false
                        )

                        // 分隔线
                        Divider()
                            .frame(height: 0.5)
                            .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                        // 通知项 2：关注通知
                        NotificationListItem(
                            avatarColor: Color(red: 0.81, green: 0.13, blue: 0.25),
                            userName: "Liam",
                            action: "started following you.",
                            time: "4d",
                            showFollowButton: true
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 通知列表项组件
struct NotificationListItem: View {
    let avatarColor: Color
    let userName: String
    let action: String
    let time: String
    let showFollowButton: Bool
    @State private var isFollowing = false

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            ZStack {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 57, height: 57)

                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 53, height: 53)
            }

            // 内容
            VStack(alignment: .leading, spacing: 2) {
                Text(userName)
                    .font(Font.custom("Helvetica Neue", size: 19).weight(.bold))
                    .foregroundColor(.black)

                HStack(spacing: 4) {
                    Text(action)
                        .font(Font.custom("Helvetica Neue", size: 15))
                        .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))

                    Text(time)
                        .font(Font.custom("Helvetica Neue", size: 13))
                        .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                }
            }

            Spacer()

            // Follow back 按钮
            if showFollowButton {
                Button(action: {
                    isFollowing.toggle()
                }) {
                    Text(isFollowing ? "Following" : "Follow back")
                        .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                        .foregroundColor(.white)
                        .padding(EdgeInsets(top: 2, leading: 18, bottom: 2, trailing: 18))
                        .frame(height: 25)
                        .background(Color(red: 0.81, green: 0.13, blue: 0.25))
                        .cornerRadius(6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

#Preview {
    NotificationView(showNotification: .constant(true))
}
