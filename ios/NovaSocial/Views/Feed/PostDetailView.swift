import SwiftUI

struct PostDetailView: View {
    let post: Post
    @StateObject private var viewModel: PostDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(post: Post) {
        self.post = post
        _viewModel = StateObject(wrappedValue: PostDetailViewModel(post: post))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                PostHeaderView(user: post.user ?? placeholderUser)
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                // Image
                AsyncImageView(url: post.imageUrl)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()

                // Action Buttons
                HStack(spacing: 16) {
                    Button {
                        viewModel.toggleLike()
                    } label: {
                        Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundColor(viewModel.isLiked ? .red : .primary)
                    }

                    Button {
                        // Focus on comment input
                    } label: {
                        Image(systemName: "bubble.right")
                            .font(.title3)
                    }

                    Button {
                        // Share
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.title3)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 12)

                // Like Count
                if viewModel.likeCount > 0 {
                    Text("\(viewModel.likeCount) likes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                // Caption
                if let caption = post.caption, !caption.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Text(post.user?.username ?? "unknown")
                            .fontWeight(.semibold)
                        Text(caption)
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Timestamp
                Text(post.createdAt.timeAgoDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 16)

                Divider()

                // Comments Section
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isLoadingComments {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.comments.isEmpty {
                        Text("No comments yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(viewModel.comments) { comment in
                            CommentCell(comment: comment)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // More options
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            CommentInputView { text in
                Task {
                    await viewModel.postComment(text)
                }
            }
        }
        .task {
            await viewModel.loadComments()
        }
    }

    private var placeholderUser: User {
        User(
            id: UUID(),
            username: "unknown",
            email: "",
            displayName: nil,
            bio: nil,
            avatarUrl: nil,
            isVerified: false,
            createdAt: Date()
        )
    }
}

struct CommentCell: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            AsyncImageView(url: comment.user?.avatarUrl)
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.user?.username ?? "unknown")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(comment.createdAt.timeAgoDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(comment.text)
                    .font(.subheadline)
            }

            Spacer()
        }
        .padding(.horizontal)
    }
}

struct CommentInputView: View {
    @State private var commentText = ""
    let onSubmit: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $commentText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(20)

            if !commentText.isEmpty {
                Button {
                    onSubmit(commentText)
                    commentText = ""
                } label: {
                    Text("Post")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 4, y: -2)
    }
}

#Preview {
    NavigationStack {
        PostDetailView(post: Post(
            id: UUID(),
            userId: UUID(),
            imageUrl: "https://picsum.photos/400/400",
            thumbnailUrl: nil,
            caption: "Sample post caption",
            likeCount: 42,
            commentCount: 5,
            isLiked: false,
            createdAt: Date(),
            user: User(
                id: UUID(),
                username: "johndoe",
                email: "john@example.com",
                displayName: "John Doe",
                bio: nil,
                avatarUrl: "https://picsum.photos/200/200",
                isVerified: true,
                createdAt: Date()
            )
        ))
    }
}
