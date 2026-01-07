import SwiftUI

/// Profile page post card - wraps the unified PostCardView
/// Maintains backward compatibility with existing code
struct ProfilePostCard: View, Equatable {
    let post: Post
    let username: String
    let avatarUrl: String?
    var isOwnPost: Bool = false
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    static func == (lhs: ProfilePostCard, rhs: ProfilePostCard) -> Bool {
        lhs.post.id == rhs.post.id &&
        lhs.post.likeCount == rhs.post.likeCount &&
        lhs.username == rhs.username &&
        lhs.avatarUrl == rhs.avatarUrl &&
        lhs.post.content == rhs.post.content &&
        lhs.isOwnPost == rhs.isOwnPost
    }

    var body: some View {
        PostCardView(
            post: post,
            username: username,
            avatarUrl: avatarUrl,
            isOwnPost: isOwnPost,
            onTap: onTap,
            onDelete: onDelete
        )
    }
}

// MARK: - Previews

#Preview("ProfilePostCard") {
    ProfilePostCard(
        post: Post(
            id: "1",
            authorId: "user1",
            content: "Cyborg dreams in neon light...",
            title: "Digital Art",
            createdAt: Int64(Date().timeIntervalSince1970),
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
            authorAvatarUrl: nil,
            location: nil,
            tags: nil,
            authorAccountType: "primary"
        ),
        username: "Simone Carter",
        avatarUrl: nil,
        isOwnPost: true
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
