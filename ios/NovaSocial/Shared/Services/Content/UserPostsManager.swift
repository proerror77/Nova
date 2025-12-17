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
    
    /// 是否正在加载更多
    var isLoadingMore = false

    /// 错误消息
    var errorMessage: String?
    
    /// 是否还有更多帖子
    var hasMore = true
    
    /// 每页加载数量
    private let pageSize = 20
    
    /// 当前加载的用户 ID
    private var currentUserId: String?

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

    /// 从服务器加载用户的帖子（首页）
    /// - Parameter userId: 用户 ID
    func loadUserPosts(userId: String) async {
        // 如果正在加载，跳过
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        currentUserId = userId
        hasMore = true

        do {
            let response = try await contentService.getPostsByAuthor(
                authorId: userId,
                limit: pageSize,
                offset: 0
            )
            // 按创建时间倒序排列
            userPosts = response.posts.sorted { $0.createdAt > $1.createdAt }
            
            // 判断是否还有更多
            hasMore = response.posts.count >= pageSize
            
            #if DEBUG
            print("[UserPostsManager] Loaded \(userPosts.count) posts for user: \(userId), hasMore: \(hasMore)")
            #endif
        } catch {
            errorMessage = error.localizedDescription
            #if DEBUG
            print("[UserPostsManager] Error loading posts: \(error)")
            #endif
        }

        isLoading = false
    }
    
    /// 加载更多帖子（分页）
    /// - Parameter userId: 用户 ID（可选，默认使用当前用户）
    func loadMorePosts(userId: String? = nil) async {
        let targetUserId = userId ?? currentUserId
        guard let targetUserId = targetUserId else { return }
        
        // 如果正在加载或没有更多，跳过
        guard !isLoadingMore, !isLoading, hasMore else { return }
        
        isLoadingMore = true
        
        do {
            let offset = userPosts.count
            let response = try await contentService.getPostsByAuthor(
                authorId: targetUserId,
                limit: pageSize,
                offset: offset
            )
            
            // 按创建时间倒序排列并去重
            let newPosts = response.posts.sorted { $0.createdAt > $1.createdAt }
            let existingIds = Set(userPosts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }
            
            userPosts.append(contentsOf: uniqueNewPosts)
            
            // 判断是否还有更多
            hasMore = response.posts.count >= pageSize
            
            #if DEBUG
            print("[UserPostsManager] Loaded \(uniqueNewPosts.count) more posts, total: \(userPosts.count), hasMore: \(hasMore)")
            #endif
        } catch {
            #if DEBUG
            print("[UserPostsManager] Error loading more posts: \(error)")
            #endif
        }
        
        isLoadingMore = false
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
        currentUserId = nil
        hasMore = true
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
