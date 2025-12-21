import SwiftUI

/// Profile 页面的帖子卡片组件
/// 显示用户头像、用户名、点赞数、图片和内容摘要
/// 实现 Equatable 以减少不必要的视图重绘
struct ProfilePostCard: View, Equatable {
    let post: Post
    let username: String
    let avatarUrl: String?
    var isOwnPost: Bool = false  // 是否为自己的帖子（控制删除选项显示）
    var onTap: (() -> Void)? = nil  // 点击卡片回调
    var onDelete: (() -> Void)? = nil  // 删除帖子回调

    // Equatable 实现 - 基于关键属性比较，避免不必要的重绘
    // 注意：回调函数不参与相等性比较
    static func == (lhs: ProfilePostCard, rhs: ProfilePostCard) -> Bool {
        lhs.post.id == rhs.post.id &&
        lhs.post.likeCount == rhs.post.likeCount &&
        lhs.username == rhs.username &&
        lhs.avatarUrl == rhs.avatarUrl &&
        lhs.post.content == rhs.post.content &&
        lhs.isOwnPost == rhs.isOwnPost
    }

    // 内容摘要（最多显示一定字数）
    private var contentPreview: String {
        let maxLength = 25
        if post.content.count > maxLength {
            return String(post.content.prefix(maxLength)) + "..."
        }
        return post.content
    }

    // 格式化点赞数
    private var formattedLikeCount: String {
        let count = post.likeCount ?? 0
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
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

                // 右侧：点赞图标 + 数量 - 使用 Symbol Effects 和 numericText 动画
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
            if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        .contextMenu {
            // 分享按钮
            Button {
                // TODO: Implement share functionality
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
            }

            // 删除按钮 - 仅对自己的帖子显示
            if isOwnPost {
                Divider()

                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("刪除貼文", systemImage: "trash")
                }
            }
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
            if let mediaUrls = post.mediaUrls, let firstUrl = mediaUrls.first, let url = URL(string: firstUrl) {
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

#Preview("PostCard - Default") {
    ProfilePostCard(
        post: Post(
            id: "1",
            authorId: "user1",
            content: "Cyborg dreams in neon light...",
            createdAt: Int64(Date().timeIntervalSince1970 - 86400),
            updatedAt: Int64(Date().timeIntervalSince1970),
            status: "published",
            mediaUrls: nil,
            mediaType: nil,
            likeCount: 2234,
            commentCount: 5,
            shareCount: 2,
            bookmarkCount: nil,
            authorUsername: "simone_carter",
            authorDisplayName: "Simone Carter",
            authorAvatarUrl: nil
        ),
        username: "Simone Carter",
        avatarUrl: nil
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("PostCard - Dark Mode") {
    ProfilePostCard(
        post: Post(
            id: "1",
            authorId: "user1",
            content: "Cyborg dreams in neon light...",
            createdAt: Int64(Date().timeIntervalSince1970 - 86400),
            updatedAt: Int64(Date().timeIntervalSince1970),
            status: "published",
            mediaUrls: nil,
            mediaType: nil,
            likeCount: 2234,
            commentCount: 5,
            shareCount: 2,
            bookmarkCount: nil,
            authorUsername: "simone_carter",
            authorDisplayName: "Simone Carter",
            authorAvatarUrl: nil
        ),
        username: "Simone Carter",
        avatarUrl: nil
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    .preferredColorScheme(.dark)
}

#Preview("PostCard - Grid") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(0..<4) { index in
                ProfilePostCard(
                    post: Post(
                        id: "\(index)",
                        authorId: "user1",
                        content: "Cyborg dreams in neon light...",
                        createdAt: Int64(Date().timeIntervalSince1970 - 86400),
                        updatedAt: Int64(Date().timeIntervalSince1970),
                        status: "published",
                        mediaUrls: nil,
                        mediaType: nil,
                        likeCount: 2234,
                        commentCount: 5,
                        shareCount: 2,
                        bookmarkCount: nil,
                        authorUsername: "simone_carter",
                        authorDisplayName: "Simone Carter",
                        authorAvatarUrl: nil
                    ),
                    username: "Simone Carter",
                    avatarUrl: nil
                )
            }
        }
        .padding(8)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("PostCard - Grid Dark Mode") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(0..<4) { index in
                ProfilePostCard(
                    post: Post(
                        id: "\(index)",
                        authorId: "user1",
                        content: "Cyborg dreams in neon light...",
                        createdAt: Int64(Date().timeIntervalSince1970 - 86400),
                        updatedAt: Int64(Date().timeIntervalSince1970),
                        status: "published",
                        mediaUrls: nil,
                        mediaType: nil,
                        likeCount: 2234,
                        commentCount: 5,
                        shareCount: 2,
                        bookmarkCount: nil,
                        authorUsername: "simone_carter",
                        authorDisplayName: "Simone Carter",
                        authorAvatarUrl: nil
                    ),
                    username: "Simone Carter",
                    avatarUrl: nil
                )
            }
        }
        .padding(8)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    .preferredColorScheme(.dark)
}
