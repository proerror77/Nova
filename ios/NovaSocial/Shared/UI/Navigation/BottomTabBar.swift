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
        ZStack {
            // Home Tab
            ZStack {
                Image(isHome ? "home-icon" : "home-icon-black")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24.s, height: 24.s)
                    .offset(y: -6.h)
                Text("Home")
                    .font(Font.custom("SF Pro", size: 9.f))
                    .foregroundColor(isHome ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                    .offset(y: 11.50.h)
            }
            .frame(width: 50.s, height: 50.s)
            .contentShape(Rectangle())
            .offset(x: -135.36.w, y: -7.h)
            .onTapGesture {
                selectTab(.home, tab: .home)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Home")
            .accessibilityHint("Navigate to home feed")
            .accessibilityAddTraits(isHome ? [.isButton, .isSelected] : .isButton)

            // Message Tab
            ZStack {
                Image(isMessage ? "Message-icon-red" : "Message-icon-black")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18.s, height: 18.s)
                    .offset(y: -6.h)
                Text("Message")
                    .font(Font.custom("SF Pro", size: 9.f))
                    .foregroundColor(isMessage ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                    .offset(y: 11.50.h)
            }
            .frame(width: 50.s, height: 50.s)
            .contentShape(Rectangle())
            .offset(x: -69.18.w, y: -7.h)
            .onTapGesture {
                selectTab(.message, tab: .message)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Messages")
            .accessibilityHint("View your messages and conversations")
            .accessibilityAddTraits(isMessage ? [.isButton, .isSelected] : .isButton)

            // New Post Button (Center)
            ZStack {
                Rectangle()
                    .foregroundColor(.clear)
                    .frame(width: 44.s, height: 32.s)
                    .background(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .cornerRadius(11.s)
                Image(systemName: "plus")
                    .font(.system(size: 18.f, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 50.s, height: 50.s)
            .contentShape(Rectangle())
            .offset(x: 0.56.w, y: -7.h)
            .onTapGesture {
                if DraftManager.hasDraft() {
                    showNewPost = true
                } else {
                    showPhotoOptions = true
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Create new post")
            .accessibilityHint("Create a new post with photos or text")
            .accessibilityAddTraits(.isButton)

            // Alice Tab
            ZStack {
                Image(isAlice ? "alice-button-on" : "alice-button-off")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36.s, height: 36.s)
            }
            .frame(width: 50.s, height: 50.s)
            .contentShape(Rectangle())
            .offset(x: 71.19.w, y: -7.h)
            .onTapGesture {
                selectTab(.alice, tab: .alice)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Alice AI")
            .accessibilityHint("Chat with Alice AI assistant")
            .accessibilityAddTraits(isAlice ? [.isButton, .isSelected] : .isButton)

            // Account Tab
            ZStack {
                // 头像边框圆圈
                Ellipse()
                    .foregroundColor(.clear)
                    .frame(width: 24.06.s, height: 24.06.s)
                    .overlay(
                        Ellipse()
                            .inset(by: 0.50)
                            .stroke(isAccount ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray.opacity(0.3), lineWidth: 0.50)
                    )
                    .offset(y: -6.h)

                // 头像内容
                ZStack {
                    if let pendingAvatar = avatarManager.pendingAvatar {
                        Image(uiImage: pendingAvatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20.s, height: 20.s)
                            .clipShape(Circle())
                    } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                              let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 20.s, height: 20.s)
                                    .clipShape(Circle())
                            case .failure(_), .empty:
                                DefaultAvatarView(size: 20.s)
                            @unknown default:
                                DefaultAvatarView(size: 20.s)
                            }
                        }
                    } else {
                        DefaultAvatarView(size: 20.s)
                    }
                }
                .frame(width: 20.s, height: 20.s)
                .offset(y: -6.h)

                Text("Account")
                    .font(Font.custom("SF Pro", size: 9.f))
                    .foregroundColor(isAccount ? Color(red: 0.87, green: 0.11, blue: 0.26) : .black)
                    .offset(y: 11.50.h)
            }
            .frame(width: 50.s, height: 50.s)
            .contentShape(Rectangle())
            .offset(x: 136.37.w, y: -7.h)
            .onTapGesture {
                selectTab(.account, tab: .account)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Account")
            .accessibilityHint("View your profile and account settings")
            .accessibilityAddTraits(isAccount ? [.isButton, .isSelected] : .isButton)
        }
        .frame(width: 375.w, height: 72.h)
        .background(DesignTokens.cardBackground)
        .ignoresSafeArea(edges: .bottom)
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
