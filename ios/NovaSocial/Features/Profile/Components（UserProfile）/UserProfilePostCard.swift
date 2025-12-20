import SwiftUI

/// UserProfile 页面的帖子卡片组件
/// 与 ProfilePostCard 样式完全一致
/// 显示用户头像、用户名、点赞数、图片和内容摘要
/// 实现 Equatable 以减少不必要的视图重绘
struct UserProfilePostCard: View, Equatable {
    // Data
    var avatarUrl: String?
    var username: String = "User"
    var likeCount: Int = 0
    var imageUrl: String?
    var content: String = ""
    var onTap: (() -> Void)? = nil
    
    // Equatable 实现 - 基于关键属性比较，避免不必要的重绘
    static func == (lhs: UserProfilePostCard, rhs: UserProfilePostCard) -> Bool {
        lhs.avatarUrl == rhs.avatarUrl &&
        lhs.username == rhs.username &&
        lhs.likeCount == rhs.likeCount &&
        lhs.imageUrl == rhs.imageUrl &&
        lhs.content == rhs.content
    }

    // 内容摘要（最多显示25个字符）
    private var contentPreview: String {
        let maxLength = 25
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
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
            // MARK: - 顶部用户信息 + 点赞数
            HStack {
                // 左侧：头像 + 用户名
                HStack(spacing: 5) {
                    avatarView
                        .frame(width: 17, height: 17)

                    Text(username)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(red: 0.02, green: 0, blue: 0))
                        .lineLimit(1)
                }

                Spacer()

                // 右侧：点赞图标 + 数量 - 使用 numericText 动画
                HStack(spacing: 2) {
                    Image(systemName: "heart")
                        .font(.system(size: 8))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    Text(formattedLikeCount)
                        .font(.system(size: 7))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        .contentTransition(.numericText())  // iOS 17+ 数字变化动画
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // MARK: - 图片区域
            imageSection
                .frame(width: 158, height: 216)
                .cornerRadius(6)
                .padding(.horizontal, 6)

            // MARK: - 底部内容预览
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(username) \(contentPreview)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            } else {
                Spacer()
                    .frame(height: 10)
            }
        }
        .frame(width: 170)
        .background(.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - Avatar View
    // 使用 CachedAsyncImage 优化头像加载性能，支持磁盘缓存
    @ViewBuilder
    private var avatarView: some View {
        if let urlString = avatarUrl, let url = URL(string: urlString) {
            CachedAsyncImage(
                url: url,
                targetSize: CGSize(width: 34, height: 34),  // 2x for retina
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
        Circle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
    }

    // MARK: - Image Section
    // 使用 CachedAsyncImage 优化帖子图片加载，支持渐进式加载和磁盘缓存
    private var imageSection: some View {
        Group {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                // 显示真实图片 - 使用 CachedAsyncImage 优化性能
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: 316, height: 432),  // 2x for retina
                    enableProgressiveLoading: true,
                    priority: .normal
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 158, height: 216)
                        .clipped()
                } placeholder: {
                    imagePlaceholder
                }
            } else {
                // 占位图
                imagePlaceholder
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
            .frame(width: 158, height: 216)
    }
}

// MARK: - Previews

#Preview("UserProfilePostCard - Default") {
    UserProfilePostCard(
        username: "Juliette",
        likeCount: 2234,
        content: "Cyborg dreams in neon light..."
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("UserProfilePostCard - With Image") {
    UserProfilePostCard(
        avatarUrl: nil,
        username: "proerror",
        likeCount: 0,
        imageUrl: "https://picsum.photos/400/600",
        content: "Dfsfsdfsdf"
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("UserProfilePostCard - Grid") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(0..<4) { index in
                UserProfilePostCard(
                    username: "Juliette",
                    likeCount: 2234,
                    content: "Cyborg dreams in neon light..."
                )
            }
        }
        .padding(8)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
