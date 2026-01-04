import SwiftUI

/// Unified post card component for profile grids
/// Used by both ProfileView (own posts) and UserProfileView (other users' posts)
/// Implements Equatable to reduce unnecessary view redraws
struct PostCardView: View, Equatable {
    // Core data
    let avatarUrl: String?
    let username: String
    let likeCount: Int
    let imageUrl: String?
    let content: String

    // Optional features (for own posts)
    var isOwnPost: Bool = false
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    // Equatable - callbacks not compared
    static func == (lhs: PostCardView, rhs: PostCardView) -> Bool {
        lhs.avatarUrl == rhs.avatarUrl &&
        lhs.username == rhs.username &&
        lhs.likeCount == rhs.likeCount &&
        lhs.imageUrl == rhs.imageUrl &&
        lhs.content == rhs.content &&
        lhs.isOwnPost == rhs.isOwnPost
    }

    // MARK: - Convenience initializer from Post

    init(
        post: Post,
        username: String? = nil,
        avatarUrl: String? = nil,
        isOwnPost: Bool = false,
        onTap: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.avatarUrl = avatarUrl ?? post.authorAvatarUrl
        self.username = username ?? post.authorDisplayName ?? post.authorUsername ?? "User"
        self.likeCount = post.likeCount ?? 0
        self.imageUrl = post.mediaUrls?.first
        self.content = post.content
        self.isOwnPost = isOwnPost
        self.onTap = onTap
        self.onDelete = onDelete
    }

    // MARK: - Direct property initializer

    init(
        avatarUrl: String? = nil,
        username: String = "User",
        likeCount: Int = 0,
        imageUrl: String? = nil,
        content: String = "",
        isOwnPost: Bool = false,
        onTap: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.avatarUrl = avatarUrl
        self.username = username
        self.likeCount = likeCount
        self.imageUrl = imageUrl
        self.content = content
        self.isOwnPost = isOwnPost
        self.onTap = onTap
        self.onDelete = onDelete
    }

    // MARK: - Computed Properties

    private var contentPreview: String {
        let maxLength = 25
        if content.count > maxLength {
            return String(content.prefix(maxLength)) + "..."
        }
        return content
    }

    private var formattedLikeCount: String {
        if likeCount >= 1000 {
            return String(format: "%.1fk", Double(likeCount) / 1000.0)
        }
        return "\(likeCount)"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: Avatar + Username + Like count
            HStack {
                HStack(spacing: 5) {
                    avatarView
                        .frame(width: 17, height: 17)

                    Text(username)
                        .font(Font.custom("SFProDisplay-Medium", size: 8.f))
                        .foregroundColor(Color(red: 0.02, green: 0, blue: 0))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: "heart")
                        .font(Font.custom("SFProDisplay-Regular", size: 8.f))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    Text(formattedLikeCount)
                        .font(Font.custom("SFProDisplay-Regular", size: 7.f))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Image
            imageSection
                .frame(width: 158, height: 216)
                .cornerRadius(6)
                .padding(.horizontal, 6)

            // Content preview
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(username) \(contentPreview)")
                    .font(Font.custom("SFProDisplay-Semibold", size: 9.f))
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
            Button {
                // Share functionality
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            if isOwnPost {
                Divider()

                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
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
        Circle()
            .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
    }

    // MARK: - Image Section

    private var imageSection: some View {
        Group {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(
                    url: url,
                    targetSize: CGSize(width: 316, height: 432),
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

#Preview("PostCardView - From Post") {
    PostCardView(
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
            tags: nil
        ),
        isOwnPost: true
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}

#Preview("PostCardView - Direct Props") {
    PostCardView(
        username: "Juliette",
        likeCount: 2234,
        content: "Cyborg dreams in neon light..."
    )
    .padding()
    .background(Color(red: 0.97, green: 0.97, blue: 0.97))
}
