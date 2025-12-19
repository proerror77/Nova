import Foundation
import SwiftUI

/// 用户帖子管理器 - 单例模式
/// 用于在应用内实时同步用户发布的帖子
@Observable
@MainActor
final class UserPostsManager {
    // MARK: - Singleton
    static let shared = UserPostsManager()

    // MARK: - Properties
    /// 用户发布的所有帖子（按时间倒序）
    private(set) var userPosts: [Post] = []

    /// 是否正在加载
    var isLoading = false

    /// 错误消息
    var errorMessage: String?

    // MARK: - Services
    private let contentService = ContentService()

    // MARK: - Private Init
    private init() {}

    // MARK: - Public Methods

    /// 添加新发布的帖子到列表顶部
    /// - Parameter post: 新发布的帖子
    func addNewPost(_ post: Post) {
        // 插入到列表顶部
        userPosts.insert(post, at: 0)
        #if DEBUG
        print("[UserPostsManager] Added new post: \(post.id), total: \(userPosts.count)")
        #endif
    }

    /// 从服务器加载用户的所有帖子
    /// - Parameter userId: 用户 ID
    func loadUserPosts(userId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await contentService.getPostsByAuthor(authorId: userId)
            // 按创建时间倒序排列
            userPosts = response.posts.sorted { $0.createdAt > $1.createdAt }
            #if DEBUG
            print("[UserPostsManager] Loaded \(userPosts.count) posts for user: \(userId)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[UserPostsManager] Error loading posts: \(error)")
            #endif
        }

        isLoading = false
    }

    /// 刷新帖子列表
    /// - Parameter userId: 用户 ID
    func refreshPosts(userId: String) async {
        await loadUserPosts(userId: userId)
    }

    /// 删除帖子
    /// - Parameter postId: 帖子 ID
    func deletePost(postId: String) {
        userPosts.removeAll { $0.id == postId }
    }

    /// 清空所有帖子（用于登出）
    func clearPosts() {
        userPosts.removeAll()
    }

    /// 检查是否有帖子
    var hasPosts: Bool {
        !userPosts.isEmpty
    }

    /// 帖子数量
    var postCount: Int {
        userPosts.count
    }
}
