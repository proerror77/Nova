import Foundation

/// Profile ViewModel - Example of fully optimized state management
@MainActor
class ProfileViewModel: BaseViewModel {
    @Published var user: User?
    @Published var posts: [Post] = []
    @Published var isFollowing: Bool = false
    @Published var showEditProfile: Bool = false

    private let userId: String
    private let repository: ProfileRepository

    init(userId: String, repository: ProfileRepository = ProfileRepository()) {
        self.userId = userId
        self.repository = repository
        super.init()
    }

    // MARK: - Load Profile
    func loadProfile() async {
        do {
            try await withLoading {
                let profile = try await repository.fetchProfile(userId: userId)
                self.user = profile.user
                self.posts = profile.posts
                self.isFollowing = profile.isFollowing
            }
        } catch {
            handleError(error)
        }
    }

    // MARK: - Follow/Unfollow
    func toggleFollow() async {
        guard let user = user else { return }

        // Optimistic update
        let previousState = isFollowing
        isFollowing.toggle()

        do {
            if previousState {
                try await repository.unfollowUser(userId: user.id)
            } else {
                try await repository.followUser(userId: user.id)
            }
        } catch {
            // Revert on error
            isFollowing = previousState
            handleError(error)
        }
    }

    // MARK: - Edit Profile
    func updateProfile(displayName: String, bio: String, avatarData: Data?) async {
        do {
            try await withLoading {
                let updatedUser = try await repository.updateProfile(
                    userId: userId,
                    displayName: displayName,
                    bio: bio,
                    avatarData: avatarData
                )
                self.user = updatedUser
                self.showEditProfile = false
            }
        } catch {
            handleError(error)
        }
    }
}

// MARK: - Mock Repository
class ProfileRepository {
    func fetchProfile(userId: String) async throws -> ProfileResponse {
        // TODO: Replace with actual API call
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return ProfileResponse(
            user: User(
                id: userId,
                username: "johndoe",
                displayName: "John Doe",
                avatarURL: nil,
                bio: "Photography enthusiast",
                followersCount: 1234,
                followingCount: 567,
                postsCount: 89
            ),
            posts: [],
            isFollowing: false
        )
    }

    func followUser(userId: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func unfollowUser(userId: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    func updateProfile(userId: String, displayName: String, bio: String, avatarData: Data?) async throws -> User {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return User(
            id: userId,
            username: "johndoe",
            displayName: displayName,
            avatarURL: nil,
            bio: bio,
            followersCount: 1234,
            followingCount: 567,
            postsCount: 89
        )
    }
}

struct ProfileResponse {
    let user: User
    let posts: [Post]
    let isFollowing: Bool
}
