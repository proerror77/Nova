import SwiftUI

// MARK: - Bottom Tab Bar

struct BottomTabBar: View {
    @Binding var currentPage: AppPage
    @Binding var showPhotoOptions: Bool

    // 头像管理
    @State private var avatarManager = AvatarManager.shared
    @State private var authManager = AuthenticationManager.shared

    private var isHome: Bool { currentPage == .home }
    private var isMessage: Bool { currentPage == .message }
    private var isAccount: Bool { currentPage == .account }
    private var isAlice: Bool { currentPage == .alice }

    var body: some View {
        HStack(spacing: -20) {
            // Home
            VStack(spacing: 3) {
                Image(isHome ? "home-icon" : "home-icon-black")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 33, height: 23)
                Text("Home")
                    .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                    .foregroundColor(isHome ? DesignTokens.accentColor : .black)
                    .offset(x: 0)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .home
            }

            // Message
            VStack(spacing: DesignTokens.spacing4) {
                Image(isMessage ? "Message-icon-red" : "Message-icon-black")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("Message")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundColor(isMessage ? DesignTokens.accentColor : .black)
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .message
            }

            // New Post
            NewPostButtonComponent(showNewPost: $showPhotoOptions)

            // Alice
            VStack(spacing: -12) {
                Image(isAlice ? "alice-button-on" : "alice-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("")
                    .font(.system(size: DesignTokens.fontCaption))
            }
            .frame(maxWidth: .infinity)
            .onTapGesture {
                currentPage = .alice
            }

            // Account
            VStack(spacing: 0) {
                ZStack {
                    // 背景圆圈
                    Circle()
                        .fill(isAccount ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.clear)
                        .frame(width: 32, height: 32)

                    // 头像
                    if let pendingAvatar = avatarManager.pendingAvatar {
                        // 优先显示待上传的头像
                        Image(uiImage: pendingAvatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                              let url = URL(string: avatarUrl) {
                        // 显示服务器头像
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 26, height: 26)
                                    .clipShape(Circle())
                            case .failure(_), .empty:
                                // 加载失败或空状态，显示iOS默认联系人图标
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 26, height: 26)
                                    .foregroundColor(Color(red: 0.78, green: 0.78, blue: 0.78))
                            @unknown default:
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 26, height: 26)
                                    .foregroundColor(Color(red: 0.78, green: 0.78, blue: 0.78))
                            }
                        }
                    } else {
                        // 默认iOS联系人图标（灰色）
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundColor(Color(red: 0.78, green: 0.78, blue: 0.78))
                    }
                }

                Text("Account")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundColor(isAccount ? DesignTokens.accentColor : .black)
            }
            .frame(maxWidth: .infinity)
            .offset(y: 0)
            .onTapGesture {
                currentPage = .account
            }
        }
        .frame(height: DesignTokens.bottomBarHeight)
        .padding(.bottom, 30) // ← 调整底部留白
        .background(
            DesignTokens.cardBackground
                .ignoresSafeArea(edges: .bottom)
        )
        .border(DesignTokens.borderColor, width: 0.5)
        .offset(y: 40) // ← 调整整体垂直位置：负值向上，正值向下
    }
}

// MARK: - New Post Button Component

struct NewPostButtonComponent: View {
    @State private var isPressed = false
    @Binding var showNewPost: Bool

    var body: some View {
        VStack(spacing: -10) {
            Image("Newpost-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .opacity(isPressed ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPressed)
            Text("")
                .font(.system(size: DesignTokens.fontCaption))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showNewPost = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPressed = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        BottomTabBar(
            currentPage: .constant(.home),
            showPhotoOptions: .constant(false)
        )
    }
}
