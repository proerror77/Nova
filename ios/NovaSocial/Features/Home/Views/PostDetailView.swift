import SwiftUI

// MARK: - Post Detail View

struct PostDetailView: View {
    let post: FeedPost
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var currentImageIndex = 0
    @State private var isFollowing = false
    @State private var showComments = false

    // Sample comments data (will be replaced with API data)
    private let sampleComments: [CommentData] = [
        CommentData(
            id: "1",
            authorName: "Lucy Liu",
            authorAvatar: nil,
            content: "Let's give it a thumbs up together.",
            timeAgo: "2d ago",
            location: "Beijing",
            likeCount: 12,
            starCount: 10,
            replies: [
                ReplyData(
                    id: "1-1",
                    authorName: "Lusin",
                    authorAvatar: nil,
                    content: "Haha, this is alice who was bribed.",
                    timeAgo: "2d ago",
                    location: "Beijing",
                    likeCount: 12,
                    starCount: 10
                )
            ],
            totalReplies: 3
        ),
        CommentData(
            id: "2",
            authorName: "Ben",
            authorAvatar: nil,
            content: "Nice shot!",
            timeAgo: "2d ago",
            location: "Beijing",
            likeCount: 12,
            starCount: 10,
            replies: [],
            totalReplies: 0
        ),
        CommentData(
            id: "3",
            authorName: "Jordyn",
            authorAvatar: nil,
            content: "Love EOs! We have TY and plant",
            timeAgo: "2d ago",
            location: "Beijing",
            likeCount: 12,
            starCount: 10,
            replies: [],
            totalReplies: 0
        )
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            // Main Content
            VStack(spacing: 0) {
                // MARK: - Top Navigation Bar
                topNavigationBar

                // MARK: - Scrollable Content
                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: - Image Carousel
                        imageCarouselSection

                        // MARK: - Content Section
                        contentSection

                        // MARK: - Comments Section
                        commentsSection

                        // Bottom padding for action bar
                        Color.clear.frame(height: 100)
                    }
                }
            }

            // MARK: - Bottom Action Bar
            bottomActionBar
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Back Button
                Button(action: {
                    if let onDismiss = onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)
                        .frame(width: 24, height: 24)
                }

                // User Info
                HStack(spacing: 10) {
                    AvatarView(image: nil, url: post.authorAvatar, size: 36)

                    Text(post.authorName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    // Verified Badge
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.20, green: 0.60, blue: 1.0))
                }

                Spacer()

                // Follow Button
                Button(action: { isFollowing.toggle() }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 12))
                        .foregroundColor(isFollowing ? DesignTokens.textSecondary : DesignTokens.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(isFollowing ? DesignTokens.textSecondary : DesignTokens.accentColor, lineWidth: 0.5)
                        )
                }

                // Share Button
                Button(action: {}) {
                    Image("card-share-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(DesignTokens.surface)

            // Divider
            Divider()
                .frame(height: 0.25)
                .background(Color(red: 0.77, green: 0.77, blue: 0.77))
        }
    }

    // MARK: - Image Carousel Section

    private var imageCarouselSection: some View {
        VStack(spacing: 8) {
            if !post.displayMediaUrls.isEmpty {
                // Image Carousel
                TabView(selection: $currentImageIndex) {
                    ForEach(Array(post.displayMediaUrls.enumerated()), id: \.offset) { index, imageUrl in
                        AsyncImage(url: URL(string: imageUrl)) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                    .overlay(ProgressView().tint(.white))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Rectangle()
                                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.5))
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3/4, contentMode: .fill)
                        .clipped()
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: UIScreen.main.bounds.width * 4 / 3 - 40)

                // Page Indicators
                if post.displayMediaUrls.count > 1 {
                    HStack(spacing: 11) {
                        ForEach(0..<post.displayMediaUrls.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentImageIndex ?
                                      Color(red: 0.81, green: 0.13, blue: 0.25) :
                                      Color(red: 0.85, green: 0.85, blue: 0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                // Placeholder for empty image
                Rectangle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(height: 332)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text("Beautiful scenery")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignTokens.textPrimary)

            // Description
            Text(post.content.isEmpty ? "The setting sun dyed the entire sea surface golden. The ship seemed to slowly sail into the light." : post.content)
                .font(.system(size: 12))
                .lineSpacing(6)
                .foregroundColor(DesignTokens.textPrimary)

            // Tags
            Text("#Fashion #Sport #Art #Beautiful")
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.accentColor)

            // Time and Location
            HStack(spacing: 5) {
                Text(post.createdAt.timeAgoDisplay())
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.textSecondary)

                Text("Beijing")
                    .font(.system(size: 10))
                    .foregroundColor(DesignTokens.textSecondary)
            }

            // Divider
            Divider()
                .frame(height: 0.2)
                .background(Color(red: 0.77, green: 0.77, blue: 0.77))
        }
        .padding(.horizontal, 17)
        .padding(.top, 16)
    }

    // MARK: - Comments Section

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Comments Count
            Text("\(post.commentCount) comments")
                .font(.system(size: 14))
                .foregroundColor(DesignTokens.textPrimary)
                .padding(.horizontal, 17)
                .padding(.top, 12)

            // Comment List
            ForEach(sampleComments) { comment in
                CommentItemView(comment: comment)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.25)
                .background(Color(red: 0.77, green: 0.77, blue: 0.77))

            HStack(spacing: 10) {
                // Like
                HStack(spacing: 6) {
                    Image("card-heart-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("\(post.likeCount)")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                // Comment
                HStack(spacing: 6) {
                    Image("card-comment-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("\(post.commentCount)")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                // Bookmark
                HStack(spacing: 6) {
                    Image("card-star-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text("\(post.shareCount)")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 16)
            .background(DesignTokens.surface)
        }
        .background(DesignTokens.surface)
    }
}

// MARK: - Comment Data Models

struct CommentData: Identifiable {
    let id: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let timeAgo: String
    let location: String
    let likeCount: Int
    let starCount: Int
    let replies: [ReplyData]
    let totalReplies: Int
}

struct ReplyData: Identifiable {
    let id: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let timeAgo: String
    let location: String
    let likeCount: Int
    let starCount: Int
}

// MARK: - Comment Item View

struct CommentItemView: View {
    let comment: CommentData
    @State private var showAllReplies = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Comment
            HStack(alignment: .top, spacing: 10) {
                // Avatar
                AvatarView(image: nil, url: comment.authorAvatar, size: 30)

                // Comment Content
                VStack(alignment: .leading, spacing: 5) {
                    // Author Name
                    Text(comment.authorName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignTokens.textSecondary)

                    // Comment Text
                    Text(comment.content)
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textPrimary)

                    // Time, Location, Reply
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Text(comment.timeAgo)
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                            Text(comment.location)
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        Button(action: {}) {
                            Text("Reply")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                        }
                    }
                }

                Spacer()

                // Like & Star Counts
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 2) {
                        Image(systemName: "heart")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text("\(comment.likeCount)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "star")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text("\(comment.starCount)")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 8)

            // Replies
            if !comment.replies.isEmpty {
                ForEach(comment.replies) { reply in
                    ReplyItemView(reply: reply)
                }

                // View More Replies
                if comment.totalReplies > comment.replies.count {
                    Button(action: { showAllReplies.toggle() }) {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(Color(red: 0.53, green: 0.53, blue: 0.53))
                                .frame(width: 28, height: 0.25)

                            Text("View \(comment.totalReplies) replies")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }
                    .padding(.leading, 57)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Reply Item View

struct ReplyItemView: View {
    let reply: ReplyData

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            AvatarView(image: nil, url: reply.authorAvatar, size: 20)

            // Reply Content
            VStack(alignment: .leading, spacing: 5) {
                // Author Name
                Text(reply.authorName)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.textSecondary)

                // Reply Text
                Text(reply.content)
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.textPrimary)

                // Time, Location, Reply
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Text(reply.timeAgo)
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.textSecondary)
                        Text(reply.location)
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.textSecondary)
                    }

                    Button(action: {}) {
                        Text("Reply")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    }
                }
            }

            Spacer()

            // Like & Star Counts
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "heart")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary)
                    Text("\(reply.likeCount)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                }

                HStack(spacing: 2) {
                    Image(systemName: "star")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary)
                    Text("\(reply.starCount)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                }
            }
        }
        .padding(.leading, 57)
        .padding(.trailing, 17)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PostDetailView(post: FeedPost.preview)
    }
}
