import SwiftUI

// MARK: - UserProfile Content Section Layout Configuration
struct UserProfileContentSectionLayout {
    // ==================== 标签栏 ====================
    var tabBarVerticalPadding: CGFloat = 16
    var tabBarFontSize: CGFloat = 16
    var searchIconSize: CGFloat = 20
    var searchIconTrailingPadding: CGFloat = 20

    // ==================== 分隔线 ====================
    var dividerHeight: CGFloat = 0.5
    var dividerColor: Color = Color(red: 0.74, green: 0.74, blue: 0.74)

    // ==================== 网格 ====================
    var gridSpacing: CGFloat = 8
    var gridPadding: CGFloat = 8
    var bottomSafeArea: CGFloat = 0  // 移除底部安全区域

    // ==================== 颜色 ====================
    var accentColor: Color = Color(red: 0.82, green: 0.11, blue: 0.26)
    var backgroundColor: Color = Color(red: 0.96, green: 0.96, blue: 0.96)
    var tabBarBackgroundColor: Color = .white
    var searchIconColor: Color = .black

    static let `default` = UserProfileContentSectionLayout()
}

// MARK: - UserProfile Content Section Component
struct UserProfileContentSection: View {
    // Data
    var posts: [UserProfilePostData] = []

    // Layout
    var layout: UserProfileContentSectionLayout = .default

    // Actions
    var onSearchTapped: () -> Void = {}
    var onPostTapped: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - 标签栏（Posts 独立居中，搜索图标右对齐）
            ZStack {
                // Posts 文字 - 完全居中
                Text("Posts")
                    .font(.system(size: layout.tabBarFontSize, weight: .bold))
                    .foregroundColor(layout.accentColor)
                    .frame(maxWidth: .infinity)

                // 搜索图标 - 右对齐，使用 Symbol Effect
                HStack {
                    Spacer()
                    Button(action: onSearchTapped) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: layout.searchIconSize))
                            .foregroundColor(layout.searchIconColor)
                            .symbolEffect(.pulse, options: .speed(0.5))  // iOS 17+ 脉冲动画
                    }
                    .padding(.trailing, layout.searchIconTrailingPadding)
                }
            }
            .padding(.vertical, layout.tabBarVerticalPadding)
            .background(layout.tabBarBackgroundColor)

            // MARK: - 分隔线
            Rectangle()
                .fill(layout.dividerColor)
                .frame(height: layout.dividerHeight)

            // MARK: - 帖子网格
            ScrollView {
                if posts.isEmpty {
                    // 空状态显示 - 使用 Symbol Effect
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.5))
                            .symbolEffect(.breathe, options: .repeat(.continuous))  // iOS 17+ 呼吸动画
                        Text("No posts yet")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: layout.gridSpacing),
                        GridItem(.flexible(), spacing: layout.gridSpacing)
                    ], spacing: layout.gridSpacing) {
                        ForEach(posts) { post in
                            UserProfilePostCard(
                                avatarUrl: post.avatarUrl,
                                username: post.username,
                                likeCount: post.likeCount,
                                imageUrl: post.imageUrl,
                                content: post.content,
                                onTap: {
                                    onPostTapped(post.id)
                                }
                            )
                        }
                    }
                    .padding(layout.gridPadding)
                    .padding(.bottom, 50)  // 为 Home Indicator 预留更多空间，确保卡片完全可见
                }
            }
            .scrollIndicators(.hidden)
            .background(layout.backgroundColor)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Post Data Model
struct UserProfilePostData: Identifiable {
    let id: String
    var avatarUrl: String?
    var username: String
    var likeCount: Int
    var imageUrl: String?
    var content: String
}

// MARK: - Previews
#Preview("UserProfileContentSection - Empty") {
    UserProfileContentSection()
}

#Preview("UserProfileContentSection - With Data") {
    UserProfileContentSection(
        posts: [
            UserProfilePostData(
                id: "1",
                username: "Juliette",
                likeCount: 2234,
                content: "Cyborg dreams..."
            ),
            UserProfilePostData(
                id: "2",
                username: "Juliette",
                likeCount: 1520,
                content: "New artwork"
            ),
            UserProfilePostData(
                id: "3",
                username: "Juliette",
                likeCount: 890,
                content: "Morning vibes"
            ),
            UserProfilePostData(
                id: "4",
                username: "Juliette",
                likeCount: 3100,
                content: "Best day ever!"
            )
        ]
    )
}
