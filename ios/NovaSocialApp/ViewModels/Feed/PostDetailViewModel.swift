import Foundation
import Combine

@MainActor
final class PostDetailViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var comments: [Comment] = []
    @Published var isLoadingComments = false
    @Published var isLiked: Bool
    @Published var likeCount: Int

    // MARK: - Private Properties
    private let post: Post
    private let postRepository = PostRepository()

    // MARK: - Initialization
    init(post: Post) {
        self.post = post
        self.isLiked = post.isLiked
        self.likeCount = post.likeCount
    }

    // MARK: - Public Methods

    func loadComments() async {
        guard !isLoadingComments else { return }

        isLoadingComments = true

        do {
            comments = try await postRepository.getComments(postId: post.id, limit: 50)
        } catch {
            // Handle error silently for now
        }

        isLoadingComments = false
    }

    func postComment(_ text: String) async {
        guard !text.isEmpty else { return }

        do {
            let newComment = try await postRepository.addComment(
                postId: post.id,
                text: text
            )
            comments.insert(newComment, at: 0)
        } catch {
            // Handle error
        }
    }

    func toggleLike() {
        let wasLiked = isLiked

        // Optimistic update
        isLiked.toggle()
        likeCount += isLiked ? 1 : -1

        Task {
            do {
                if wasLiked {
                    try await postRepository.unlikePost(postId: post.id)
                } else {
                    try await postRepository.likePost(postId: post.id)
                }
            } catch {
                // Revert on error
                isLiked = wasLiked
                likeCount = post.likeCount
            }
        }
    }
}
