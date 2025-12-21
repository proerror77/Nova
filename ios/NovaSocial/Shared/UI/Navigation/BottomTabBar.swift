import SwiftUI

// MARK: - Bottom Tab Bar

struct BottomTabBar: View {
    @Binding var currentPage: AppPage
    @Binding var showPhotoOptions: Bool
    @Binding var showNewPost: Bool  // 新增：直接打开 NewPost 页面

    // 头像管理 - 性能優化：使用 @ObservedObject 替代 @State 用於單例
    @ObservedObject private var avatarManager = AvatarManager.shared
    @EnvironmentObject private var authManager: AuthenticationManager

    // App Coordinator for tab state management
    @Environment(\.appCoordinator) private var coordinator

    private var isHome: Bool { currentPage == .home }
    private var isMessage: Bool { currentPage == .message }
    private var isAccount: Bool { currentPage == .account }
    private var isAlice: Bool { currentPage == .alice }

    /// Helper to handle tab selection with coordinator sync
    private func selectTab(_ page: AppPage, tab: MainTab) {
        // Sync with coordinator (resets navigation path on tab change)
        coordinator.selectTab(tab)
        currentPage = page
    }

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
                selectTab(.home, tab: .home)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Home")
            .accessibilityHint("Navigate to home feed")
            .accessibilityAddTraits(isHome ? [.isButton, .isSelected] : .isButton)

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
                selectTab(.message, tab: .message)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Messages")
            .accessibilityHint("View your messages and conversations")
            .accessibilityAddTraits(isMessage ? [.isButton, .isSelected] : .isButton)

            // New Post
            NewPostButtonComponent(
                showNewPost: $showPhotoOptions,
                onTapWithDraft: {
                    showNewPost = true  // 有草稿，直接打开 NewPost
                },
                onTapNoDraft: {
                    showPhotoOptions = true  // 无草稿，显示选项弹窗
                }
            )

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
                selectTab(.alice, tab: .alice)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Alice AI")
            .accessibilityHint("Chat with Alice AI assistant")
            .accessibilityAddTraits(isAlice ? [.isButton, .isSelected] : .isButton)

            // Account
            VStack(spacing: 0) {
                ZStack {
                    // 背景圆圈
                    Circle()
                        .fill(isAccount ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.clear)
                        .frame(width: 32, height: 32)

                    // 头像 - 使用统一的默认头像组件
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
                                // 加载失败或空状态，显示默认头像
                                DefaultAvatarView(size: 26)
                            @unknown default:
                                DefaultAvatarView(size: 26)
                            }
                        }
                    } else {
                        // 默认头像
                        DefaultAvatarView(size: 26)
                    }
                }

                Text("Account")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundColor(isAccount ? DesignTokens.accentColor : .black)
            }
            .frame(maxWidth: .infinity)
            .offset(y: 0)
            .onTapGesture {
                selectTab(.account, tab: .account)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Account")
            .accessibilityHint("View your profile and account settings")
            .accessibilityAddTraits(isAccount ? [.isButton, .isSelected] : .isButton)
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
    var onTapWithDraft: (() -> Void)?  // 有草稿时的回调
    var onTapNoDraft: (() -> Void)?    // 无草稿时的回调

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
                // 检查是否有草稿
                if DraftManager.hasDraft() {
                    onTapWithDraft?()
                } else {
                    onTapNoDraft?()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPressed = false
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Create new post")
        .accessibilityHint("Create a new post with photos or text")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Draft Manager
struct DraftManager {
    private static let draftTextKey = "NewPostDraftText"
    private static let draftImagesKey = "NewPostDraftImages"

    /// 检查是否有保存的草稿
    static func hasDraft() -> Bool {
        let hasText = UserDefaults.standard.string(forKey: draftTextKey)?.isEmpty == false
        let hasImages = (UserDefaults.standard.array(forKey: draftImagesKey) as? [Data])?.isEmpty == false
        return hasText || hasImages
    }
}

// MARK: - Previews

#Preview("TabBar - Default") {
    VStack {
        Spacer()
        BottomTabBar(
            currentPage: .constant(.home),
            showPhotoOptions: .constant(false),
            showNewPost: .constant(false)
        )
    }
}

#Preview("TabBar - Dark Mode") {
    VStack {
        Spacer()
        BottomTabBar(
            currentPage: .constant(.home),
            showPhotoOptions: .constant(false),
            showNewPost: .constant(false)
        )
    }
    .preferredColorScheme(.dark)
}
