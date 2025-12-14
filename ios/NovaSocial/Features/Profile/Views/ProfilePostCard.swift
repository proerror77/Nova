import SwiftUI

/// Profile 页面的帖子卡片组件
/// 显示用户头像、用户名、时间、图片和内容摘要
struct ProfilePostCard: View {
    let post: Post
    let username: String
    let avatarUrl: String?

    // 计算相对时间
    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(post.createdAt))
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))d"
        } else {
            return "\(Int(interval / 604800))w"
        }
    }

    // 内容摘要（最多显示一定字数）
    private var contentPreview: String {
        let maxLength = 30
        if post.content.count > maxLength {
            return String(post.content.prefix(maxLength)) + "..."
        }
        return post.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 顶部用户信息
            userInfoSection
                .padding(.horizontal, 8)
                .padding(.top, 8)

            // MARK: - 图片区域
            imageSection
                .padding(.top, 6)

            // MARK: - 内容预览
            if !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contentSection
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            } else {
                Spacer()
                    .frame(height: 10)
            }
        }
        .background(.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    // MARK: - User Info Section
    private var userInfoSection: some View {
        HStack(spacing: 6) {
            // 头像
            avatarView
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                // 用户名
                Text(username)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.02, green: 0, blue: 0))
                    .lineLimit(1)

                // 发布时间
                Text(relativeTime)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
            }

            Spacer()
        }
    }

    // MARK: - Avatar View
    @ViewBuilder
    private var avatarView: some View {
        if let urlString = avatarUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
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
    private var imageSection: some View {
        Group {
            if let mediaUrls = post.mediaUrls, let firstUrl = mediaUrls.first, let url = URL(string: firstUrl) {
                // 显示真实图片
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        imagePlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipped()
                    case .failure:
                        imagePlaceholder
                    @unknown default:
                        imagePlaceholder
                    }
                }
                .frame(height: 180)
            } else {
                // 占位图
                imagePlaceholder
            }
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
            .frame(height: 180)
    }

    // MARK: - Content Section
    private var contentSection: some View {
        HStack(spacing: 4) {
            Text(username)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.black)

            Text(contentPreview)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.black)
                .lineLimit(1)

            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
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
                    likeCount: 10,
                    commentCount: 5,
                    shareCount: 2,
                    authorUsername: "simone_carter",
                    authorDisplayName: "Simone Carter",
                    authorAvatarUrl: nil
                ),
                username: "Simone Carter",
                avatarUrl: nil
            )

            ProfilePostCard(
                post: Post(
                    id: "2",
                    authorId: "user1",
                    content: "Another beautiful day!",
                    createdAt: Int64(Date().timeIntervalSince1970 - 3600),
                    updatedAt: Int64(Date().timeIntervalSince1970),
                    status: "published",
                    mediaUrls: nil,
                    mediaType: nil,
                    likeCount: 25,
                    commentCount: 8,
                    shareCount: 3,
                    authorUsername: "simone_carter",
                    authorDisplayName: "Simone Carter",
                    authorAvatarUrl: nil
                ),
                username: "Simone Carter",
                avatarUrl: nil
            )
        }
        .padding(8)
    }
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
