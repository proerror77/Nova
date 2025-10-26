import Foundation

/// UserRepository - 用户业务逻辑层
/// 职责：处理用户资料、关注、搜索等操作
///
/// 改进点:
/// 1. 集成请求去重器,防止重复关注/取关
/// 2. 输入验证
/// 3. 消除重复的 Response 定义
final class UserRepository {
    private let apiClient: APIClient
    private let interceptor: RequestInterceptor
    private let deduplicator = RequestDeduplicator()

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient(baseURL: AppConfig.baseURL)
        self.interceptor = RequestInterceptor(apiClient: self.apiClient)
    }

    // MARK: - User Profile

    /// 获取用户资料
    func getUserProfile(username: String) async throws -> UserProfile {
        // 验证 username
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyInput
        }

        let endpoint = APIEndpoint(
            path: "/users/\(username)",
            method: .get
        )

        return try await interceptor.executeWithRetry(endpoint)
    }

    /// 根据用户 ID 获取资料
    func getUserProfile(userId: UUID) async throws -> UserProfile {
        let endpoint = APIEndpoint(
            path: "/users/\(userId.uuidString)",
            method: .get
        )

        return try await interceptor.executeWithRetry(endpoint)
    }

    /// 获取用户的帖子列表
    func getUserPosts(userId: UUID, cursor: String? = nil, limit: Int = 20) async throws -> [Post] {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let endpoint = APIEndpoint(
            path: "/users/\(userId.uuidString)/posts",
            method: .get,
            queryItems: queryItems
        )

        let response: PostsResponse = try await interceptor.executeWithRetry(endpoint)
        return response.posts
    }

    /// 更新当前用户资料
    func updateProfile(bio: String? = nil, avatarUrl: String? = nil, displayName: String? = nil) async throws -> User {
        // 验证输入
        if let bio = bio {
            try RequestDeduplicator.validate(bio, maxLength: 500)
        }

        if let displayName = displayName {
            try RequestDeduplicator.validate(displayName, maxLength: 50)
        }

        struct UpdateProfileRequest: Codable {
            let bio: String?
            let avatarUrl: String?
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case bio
                case avatarUrl = "avatar_url"
                case displayName = "display_name"
            }
        }

        let request = UpdateProfileRequest(
            bio: bio,
            avatarUrl: avatarUrl,
            displayName: displayName
        )

        let endpoint = APIEndpoint(
            path: "/users/me",
            method: .put,
            body: request
        )

        let response: UserResponse = try await interceptor.executeWithRetry(endpoint)
        return response.user
    }

    /// 搜索用户
    func searchUsers(query: String, limit: Int = 20) async throws -> [User] {
        // 验证搜索关键词
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyInput
        }

        let queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        let endpoint = APIEndpoint(
            path: "/users/search",
            method: .get,
            queryItems: queryItems
        )

        let response: UsersResponse = try await interceptor.executeWithRetry(endpoint)
        return response.users
    }

    // MARK: - Follow Operations (带去重)

    /// 关注用户
    /// 去重策略: 相同用户的关注请求会被自动合并
    func followUser(id: UUID) async throws -> (following: Bool, followerCount: Int) {
        let key = RequestDeduplicator.followKey(userId: id)

        return try await deduplicator.execute(key: key) {
            let endpoint = APIEndpoint(
                path: "/users/\(id.uuidString)/follow",
                method: .post
            )

            let response: FollowResponse = try await self.interceptor.executeWithRetry(endpoint)
            return (response.following, response.followerCount)
        }
    }

    func followUser(userId: UUID) async throws -> (following: Bool, followerCount: Int) {
        try await followUser(id: userId)
    }

    /// 取消关注
    func unfollowUser(id: UUID) async throws -> (following: Bool, followerCount: Int) {
        let key = RequestDeduplicator.unfollowKey(userId: id)

        return try await deduplicator.execute(key: key) {
            let endpoint = APIEndpoint(
                path: "/users/\(id.uuidString)/follow",
                method: .delete
            )

            let response: FollowResponse = try await self.interceptor.executeWithRetry(endpoint)
            return (response.following, response.followerCount)
        }
    }

    func unfollowUser(userId: UUID) async throws -> (following: Bool, followerCount: Int) {
        try await unfollowUser(id: userId)
    }

    /// 获取粉丝列表
    func getFollowers(userId: UUID, cursor: String? = nil, limit: Int = 20) async throws -> [User] {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let endpoint = APIEndpoint(
            path: "/users/\(userId.uuidString)/followers",
            method: .get,
            queryItems: queryItems
        )

        let response: UsersResponse = try await interceptor.executeWithRetry(endpoint)
        return response.users
    }

    /// 获取关注列表
    func getFollowing(userId: UUID, cursor: String? = nil, limit: Int = 20) async throws -> [User] {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let endpoint = APIEndpoint(
            path: "/users/\(userId.uuidString)/following",
            method: .get,
            queryItems: queryItems
        )

        let response: UsersResponse = try await interceptor.executeWithRetry(endpoint)
        return response.users
    }
}
