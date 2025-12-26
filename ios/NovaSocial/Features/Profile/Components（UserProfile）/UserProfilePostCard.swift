import SwiftUI

/// UserProfile page post card - wraps the unified PostCardView
/// Maintains backward compatibility with existing code
struct UserProfilePostCard: View, Equatable {
    var avatarUrl: String?
    var username: String = "User"
    var likeCount: Int = 0
    var imageUrl: String?
    var content: String = ""
    var onTap: (() -> Void)? = nil

    static func == (lhs: UserProfilePostCard, rhs: UserProfilePostCard) -> Bool {
        lhs.avatarUrl == rhs.avatarUrl &&
        lhs.username == rhs.username &&
        lhs.likeCount == rhs.likeCount &&
        lhs.imageUrl == rhs.imageUrl &&
        lhs.content == rhs.content
    }

    var body: some View {
        PostCardView(
            avatarUrl: avatarUrl,
            username: username,
            likeCount: likeCount,
            imageUrl: imageUrl,
            content: content,
            isOwnPost: false,
            onTap: onTap,
            onDelete: nil
        )
    }
}

// MARK: - Previews

#Preview("UserProfilePostCard") {
    UserProfilePostCard(
        username: "Juliette",
        likeCount: 2234,
        content: "Cyborg dreams in neon light..."
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
