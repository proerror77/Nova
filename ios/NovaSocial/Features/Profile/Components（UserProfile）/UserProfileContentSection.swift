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
    var dividerColor: Color = DesignTokens.borderColor

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
        GeometryReader { geometry in
            // MARK: - 帖子网格（标签栏已移至 UserProfileView 背景板层）
            ScrollView {
                if posts.isEmpty {
                    // 空状态 - 无内容显示
                    Spacer()
                } else {
                    // 帖子卡片网格 - 响应式2列布局
                    let cardWidth = (geometry.size.width - 15) / 2  // 5px间距 * 3 = 15
                    let cardHeight = cardWidth * 1.51  // 保持 180:272 的比例
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 5),
                        GridItem(.flexible(), spacing: 5)
                    ], spacing: 5) {
                        ForEach(posts) { post in
                            UserProfilePostCardNew(
                                avatarUrl: post.avatarUrl,
                                username: post.username,
                                likeCount: post.likeCount,
                                imageUrl: post.imageUrl,
                                content: post.content,
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                onTap: {
                                    onPostTapped(post.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 50)  // 为标签栏留出空间
                    .padding(.bottom, 100)  // 底部留出空间
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}


// MARK: - 新版帖子卡片（响应式设计）
struct UserProfilePostCardNew: View {
    // Data
    var avatarUrl: String?
    var username: String = "User"
    var likeCount: Int = 0
    var imageUrl: String?
    var content: String = ""
    var cardWidth: CGFloat
    var cardHeight: CGFloat
    var onTap: (() -> Void)? = nil

    // 内容摘要（最多显示20个字符）
    private var contentPreview: String {
        let fullText = "\(username) \(content)"
        let maxLength = 28
        if fullText.count > maxLength {
            return String(fullText.prefix(maxLength)) + "..."
        }
        return fullText
    }

    // 格式化点赞数
    private var formattedLikeCount: String {
        if likeCount >= 1000 {
            return String(format: "%.1fk", Double(likeCount) / 1000.0)
        }
        return "\(likeCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 图片区域
            imageSection
                .frame(width: cardWidth - 12, height: cardHeight * 0.75)
                .cornerRadius(6)
                .padding(.horizontal, 6)
                .padding(.top, 6)

            // MARK: - 底部内容预览
            Text(contentPreview)
                .font(Font.custom("SFProDisplay-Regular", size: 10))
                .foregroundColor(.black)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            // MARK: - 底部用户信息 + 点赞数
            HStack {
                // 左侧：头像 + 用户名
                HStack(spacing: 5) {
                    avatarView
                        .frame(width: 17, height: 17)

                    Text(username)
                        .font(Font.custom("SFProDisplay-Regular", size: 10))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                        .lineLimit(1)
                }

                Spacer()

                // 右侧：点赞图标 + 数量
                HStack(spacing: 5) {
                    Image(systemName: "heart")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                        .frame(width: 12, height: 12)

                    Text(formattedLikeCount)
                        .font(Font.custom("SFProDisplay-Regular", size: 8.18))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                }
                .frame(width: 40)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(.white)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - Avatar View
    @ViewBuilder
    private var avatarView: some View {
        if let urlString = avatarUrl, let url = URL(string: urlString) {
            CachedAsyncImage(
                url: url,
                targetSize: CGSize(width: 34, height: 34),
                enableProgressiveLoading: false,
                priority: .normal
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderAvatar
            }
            .clipShape(Circle())
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Ellipse()
            .foregroundColor(.clear)
            .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
            .clipShape(Circle())
    }

    // MARK: - Image Section
    private var imageSection: some View {
        Group {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: (cardWidth - 12) * 2, height: cardHeight * 0.75 * 2),
                    enableProgressiveLoading: true,
                    priority: .normal
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: cardWidth - 12, height: cardHeight * 0.75)
                        .clipped()
                } placeholder: {
                    imagePlaceholder
                }
            } else {
                imagePlaceholder
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
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
