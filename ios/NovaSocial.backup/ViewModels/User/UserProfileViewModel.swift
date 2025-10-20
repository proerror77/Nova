import Foundation
import Combine

@MainActor
final class UserProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var user: User?
    @Published var stats: UserStats?
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingPosts = false
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Private Properties
    private let userRepository: UserRepository
    private let postRepository: PostRepository
    private let userId: UUID?

    // MARK: - Computed Properties
    var isOwnProfile: Bool {
        // Check if this is the current user's profile
        // TODO: Compare with AuthManager.shared.currentUser?.id
        return userId == nil
    }

    // MARK: - Initialization
    init(
        userId: UUID? = nil,
        userRepository: UserRepository = UserRepository(),
        postRepository: PostRepository = PostRepository()
    ) {
        self.userId = userId
        self.userRepository = userRepository
        self.postRepository = postRepository
    }

    // MARK: - Public Methods

    func loadProfile() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            if let userId = userId {
                // Load specific user profile
                let profile = try await userRepository.getUserProfile(userId: userId)
                user = profile.user
                stats = profile.stats
            } else {
                // Load current user's profile
                if let currentUser = AuthManager.shared.currentUser {
                    user = currentUser
                    // Load stats for current user
                    let profile = try await userRepository.getUserProfile(userId: currentUser.id)
                    stats = profile.stats
                }
            }

            // Load user posts
            await loadPosts()
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isLoading = false
    }

    func loadPosts() async {
        guard let user = user, !isLoadingPosts else { return }

        isLoadingPosts = true

        do {
            posts = try await userRepository.getUserPosts(userId: user.id, limit: 50)
        } catch {
            // Handle error silently
        }

        isLoadingPosts = false
    }

    func toggleFollow() async {
        guard let user = user, let stats = stats else { return }

        let wasFollowing = stats.isFollowing

        // Optimistic update
        self.stats = UserStats(
            postCount: stats.postCount,
            followerCount: wasFollowing ? stats.followerCount - 1 : stats.followerCount + 1,
            followingCount: stats.followingCount,
            isFollowing: !wasFollowing
        )

        do {
            if wasFollowing {
                try await userRepository.unfollowUser(userId: user.id)
            } else {
                try await userRepository.followUser(userId: user.id)
            }
        } catch {
            // Revert on error
            self.stats = stats
            showErrorMessage(error.localizedDescription)
        }
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
